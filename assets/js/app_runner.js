// The `AppRunner` hook: everything that ties a module to the page.
//
// It owns the worker (the kill switch), the two sinks the component
// renders into, and the round trips to the host. The effect semantics live
// in `app_loop.js` and the memory protocol in `app_session.js`; this file is
// only the wiring between them and LiveView.
//
// One deadline covers every wait — the module loading, it starting (which
// includes its own `start` code), a `handle` that never returns, and a host
// reply that never arrives. Any of those is a reason to terminate the
// worker, which is also the only way to stop a module that is spinning.
//
// The hook is started and stopped from outside: `data-wasm-src` runs a
// module as soon as the pane mounts (the way a published app's pane does),
// and LiveView drives the playground's pane with `app-run`/`app-stop`, since
// there the module comes from an editor buffer rather than from a URL.
// Every run also records itself — what the module asked for, what came back,
// what it printed — and hands that list to `app-trace` on the LiveView, which
// is what the playground's left rail steps through.
//
// A foreign `.wasm` reaches the pane from the right rail's picker or by
// being dropped on it, and both are gated: the bytes are instantiated here,
// in this browser, and a drop-in only keeps running once a first tick comes
// back following the ABI — a refusal stops it on the spot. That gate is what
// the publish path will lean on, so it is recorded in the trace like
// everything else.
//
// Two messages come from this file rather than from the host: `tick`s on
// requestAnimationFrame once a module asks for `animate`, and `ui` events
// for the pointer over the view's canvas. Both are paced by the same rule —
// one delivery in flight at a time — so a module that draws at its own pace
// is what limits the rate, and the deadline armed over `_deliver` covers a
// tick that never comes back (§3).

import {AppLoop, fromBase64, isMap} from "./app_loop.js"
import {applyDraw, checkDraw} from "./app_draw.js"
import {buildView} from "./app_view.js"
import {encode} from "./cbor.js"
const DEADLINE_MS = 5000
const PRINT_LIMIT = 64 * 1024
const TRACE_LIMIT = 200
const TRACE_DETAIL_LIMIT = 400
const TRACE_FLUSH_MS = 120
// Pointer events arrive faster than any module answers them, so the queue
// between the pane and the worker is bounded: moves coalesce into the one
// sample waiting, and past the cap the oldest entry goes rather than the
// newest — a down or an up is worth more than a stale move.
const UI_QUEUE_LIMIT = 8
// Somebody else's artifact, so the drop-in gets the order of magnitude of
// the artifact budget rather than the buffer's own size cap.
const MAX_WASM_BYTES = 4 * 1024 * 1024

export const AppRunner = {
  mounted() {
    this._worker = null
    this._timer = null
    this._trace = []
    this._traceTimer = null
    this._gate = false
    this._inFlight = false
    this._animateOn = false
    this._raf = null
    this._ui = []
    this._loop = this._newLoop()

    this.handleEvent("app-run", payload => this._run(payload || {}))
    this.handleEvent("app-stop", () => this._loop.stop("stopped"))

    // The rail's picker sits in another column and cannot reach this hook,
    // so it hands the file over on this element; dropping one on the pane is
    // the same hand-off with no rail involved.
    this._onHandoff = event => this._dropin(event.detail)
    this._onDragOver = event => {
      event.preventDefault()
      this.el.classList.add("run-pane-drop")
    }
    this._onDragLeave = event => {
      if (this.el.contains(event.relatedTarget)) return
      this.el.classList.remove("run-pane-drop")
    }
    this._onDrop = event => {
      event.preventDefault()
      this.el.classList.remove("run-pane-drop")
      const file = event.dataTransfer && event.dataTransfer.files[0]
      if (file) this._dropin(file)
    }

    this.el.addEventListener("catenary:wasm", this._onHandoff)
    this.el.addEventListener("dragenter", this._onDragOver)
    this.el.addEventListener("dragover", this._onDragOver)
    this.el.addEventListener("dragleave", this._onDragLeave)
    this.el.addEventListener("drop", this._onDrop)
    // Delegated from the pane rather than bound to each canvas: the canvas
    // is rebuilt on every render, and the pane outlives all of them.
    this._onPointer = event => this._pointer(event)
    this.el.addEventListener("pointerdown", this._onPointer)
    this.el.addEventListener("pointermove", this._onPointer)
    this.el.addEventListener("pointerup", this._onPointer)

    const src = this.el.dataset.wasmSrc
    if (src) this._load(src)
  },

  destroyed() {
    if (this._traceTimer !== null) clearTimeout(this._traceTimer)
    this._traceTimer = null
    this.el.removeEventListener("catenary:wasm", this._onHandoff)
    this.el.removeEventListener("dragenter", this._onDragOver)
    this.el.removeEventListener("dragover", this._onDragOver)
    this.el.removeEventListener("dragleave", this._onDragLeave)
    this.el.removeEventListener("drop", this._onDrop)
    this.el.removeEventListener("pointerdown", this._onPointer)
    this.el.removeEventListener("pointermove", this._onPointer)
    this.el.removeEventListener("pointerup", this._onPointer)
    this.el.classList.remove("run-pane-drop")
    this._teardown()
  },

  // A run gets a fresh loop: strikes, the stopped flag and the sinks all
  // belong to one attempt at running a module, so re-running has to build
  // them again rather than resuming a loop that already gave up.
  _newLoop() {
    const status = this.el.querySelector("#app-status")
    const print = this.el.querySelector("#app-print")
    const view = this.el.querySelector("#app-view")

    return new AppLoop({
      status: text => {
        status.textContent = text
      },
      stop: reason => {
        this._refuseGate(reason)
        this._record("stop", reason)
        this._teardown()
      },
      print: text => {
        this._record("print", text)
        print.textContent = appendPrint(print.textContent, text)
        // The console is a fixed-height window onto the log: each line the
        // module prints scrolls the tail into view rather than growing the
        // pane the way a print log left to itself would.
        print.scrollTop = print.scrollHeight
      },
      render: value => {
        // A tree that failed validation comes back with `strike`, and as
        // the text dump rather than as a half-built view.
        const built = buildView(value)
        if (built.strike) this._loop.strike(built.strike)
        this._record("render", viewShape(value))
        view.textContent = ""
        view.appendChild(built.node)
        view.classList.remove("hidden")
      },
      draw: ops => {
        // One canvas per view, the first one the tree declares: the lease
        // that keeps a viewer to one app at a time is the same one canvas
        // (§3), so a draw does not get to choose where it lands.
        const canvas = this.el.querySelector("#app-view canvas[data-app-canvas]")
        const problem = canvas ? checkDraw(ops) : "a draw with no canvas in the view"
        this._record("draw", problem ? "rejected" : `${ops.length} ops`)
        if (problem) {
          this._loop.strike(problem)
          return
        }
        try {
          const failure = applyDraw(canvas, ops)
          if (failure) this._loop.strike(failure)
        } catch (error) {
          this._loop.strike(`the draw could not be applied (${error.message})`)
        }
      },
      animate: on => {
        // The on/off is worth one trace entry; the ticks themselves are
        // not — sixty an second would push the run's own history out of
        // the rail the reader is stepping through.
        this._record("animate", on ? "on" : "off")
        if (on) this._startAnimate()
        else this._stopAnimate()
      },
      want: (op, args) => {
        this._record("want", op)
        return this._want(op, args)
      },
      publish: entry => {
        return this._publish(entry)
      },
      deliver: message => {
        this._record("reply", replyShape(message))
        return this._deliver(message)
      }
    })
  },

  // Start a run. `wasm` is the host's compilation of the buffer, `bytes` a
  // drop-in that never left the browser, `src` a URL to fetch one from, and
  // `error` a failure to produce a module at all — a status line rather than
  // a failure of the pane. `gate` marks the run as the instantiate test for
  // a foreign file, which is a different verdict from running the buffer.
  _run(payload) {
    this._teardown()
    if (this._traceTimer !== null) clearTimeout(this._traceTimer)
    this._traceTimer = null
    this._trace = []
    this._ui = []
    this._inFlight = false
    this._gate = payload.gate === true
    if (this._gate) this.pushEvent("app-run-start", {})

    const status = this.el.querySelector("#app-status")
    const print = this.el.querySelector("#app-print")
    const view = this.el.querySelector("#app-view")
    print.textContent = ""
    view.textContent = ""
    view.classList.add("hidden")

    this._loop = this._newLoop()

    if (payload.error) {
      this._refuseGate(payload.error)
      status.textContent = payload.status || `could not compile (${payload.error})`
      return
    }

    status.textContent = "starting…"
    if (payload.bytes) this._spawn(payload.bytes)
    else if (payload.wasm) this._spawn(fromBase64(payload.wasm))
    else if (payload.src) this._load(payload.src)
    else status.textContent = "nothing to run"
  },

  // A foreign module, from the rail's picker or from a drop on the pane.
  // The bytes never leave the browser: what is being gated is whether *this*
  // webview can instantiate them and get a first tick back, which is the
  // only evidence a peer running a different webview would give us anyway.
  async _dropin(blob) {
    if (!blob || typeof blob.arrayBuffer !== "function") {
      this._run({gate: true, error: "no file", status: "nothing to run"})
      return
    }

    if (blob.size > MAX_WASM_BYTES) {
      const limit = `${MAX_WASM_BYTES / (1024 * 1024)} MB`
      this._run({
        gate: true,
        error: `larger than the ${limit} drop-in limit`,
        status: `the file is larger than the ${limit} drop-in limit`
      })
      return
    }

    const bytes = new Uint8Array(await blob.arrayBuffer())
    if (!isWasm(bytes)) {
      this._run({
        gate: true,
        error: "the file is not a wasm module",
        status: "the file is not a wasm module"
      })
      return
    }

    this._run({gate: true, bytes})
  },

  // The gate speaks exactly once. A refusal from a stop (the module did not
  // load, the deadline expired, it was stopped) or from one of the checks
  // above ends it one way; the verdict after the first tick ends it the
  // other. `_gate` is the only flag, so no run can be gated twice.
  _refuseGate(reason) {
    if (!this._gate) return
    this._gate = false
    this._record("gate", `refused (${reason})`)
  },

  // The verdict comes after the first tick's effects have been applied, so
  // the module has had its chance to show what it is. Refusing is not only a
  // record: a file that did not pass the gate does not keep running here, so
  // the loop is stopped on the spot and the stop sink records the run's end
  // the way it does for any other stop. `_gate` is already closed by then,
  // so that sink finds the gate silent and it still speaks exactly once.
  _gateVerdict() {
    if (!this._gate) return
    this._gate = false
    if (this._loop.strikes > 0 || this._loop.stopped) {
      const reason = "refused (the first tick did not follow the ABI)"
      this._record("gate", reason)
      this._loop.stop(reason)
    } else {
      this._record("gate", "instantiate + first tick ok")
    }
  },

  async _load(src) {
    this._loop.sinks.status("loading module…")
    this._arm()
    try {
      const response = await fetch(src)
      if (!response.ok) throw new Error(`the server answered ${response.status}`)
      const wasm = await response.arrayBuffer()
      if (this._loop.stopped) return
      this._spawn(wasm)
    } catch (error) {
      this._loop.stop(`the module could not be loaded (${error.message})`)
    }
  },

  _spawn(wasm) {
    const worker = this.el.dataset.workerSrc
    this._worker = new Worker(worker)
    this._worker.onmessage = event => this._onWorker(event.data)
    this._worker.onerror = event => this._loop.stop(`the worker failed (${event.message})`)
    this._arm()
    // The transfer list takes buffers, not views: a module that arrived as
    // base64 is a Uint8Array, and only its buffer can move to the worker.
    const bytes = wasm instanceof Uint8Array ? wasm : new Uint8Array(wasm)
    this._worker.postMessage({type: "start", wasm: bytes}, [bytes.buffer])
  },

  async _onWorker(message) {
    if (!message) return
    switch (message.type) {
      case "ready":
        this._disarm()
        this._loop.sinks.status("running")
        this._deliver({msg: "init"})
        break
      case "effects":
        // The worker is free the moment it posts the answer, so the next
        // tick or queued pointer event may go out while this delivery's
        // effects are still being applied — the loop queues those behind
        // the array it is working on, which is what keeps two deliveries
        // from interleaving (§3).
        this._disarm()
        this._inFlight = false
        // The gate is judged on the first tick *after* its effects have been
        // applied: a module that instantiates and then hands back junk has
        // instantiated, but it has not passed. A stop during that run speaks
        // first, so the verdict below finds the gate already closed.
        await this._loop.effects(message.bytes)
        this._flushUi()
        this._gateVerdict()
        break
      case "error":
        this._inFlight = false
        this._loop.stop(`the module failed (${message.message})`)
        break
      default:
        this._loop.stop("the worker sent something unexpected")
    }
  },

  async _deliver(message) {
    if (this._loop.stopped || !this._worker) return
    const bytes = encode(message)
    this._arm()
    this._inFlight = true
    this._worker.postMessage({type: "deliver", bytes}, [bytes.buffer])
  },

  async _want(op, args) {
    if (this._loop.stopped || !this._worker) {
      throw new Error("no module is running")
    }
    if (!isMap(args)) throw new Error("the arguments are not a map")
    this._arm()
    // The pane belongs to a component, so the call has to name it. An
    // untargeted pushEvent lands on the root LiveView, which has no
    // app-want clause, and the reply never comes back. pushEventTo
    // answers with one settled result per target, so the reply is
    // unpacked here rather than handed to the loop.
    const results = await this.pushEventTo(this.el, "app-want", {
      op,
      args: toBase64(encode(args))
    })
    const first = results && results[0]
    if (!first || first.status !== "fulfilled" || !first.value) {
      throw new Error("the app view did not answer")
    }
    return first.value.reply
  },

  // One publish, one round trip. The entry goes up as base64(CBOR(entry))
  // for the same reason a want's arguments do — LiveView carries JSON, and
  // neither bytes nor arbitrary terms survive it — and the reply is handed
  // straight back to the loop, which turns a refusal into a strike.
  //
  // The deadline armed here covers a component that never answers. Unlike a
  // `want`, a publish has no reply to deliver to the module afterwards, so
  // it is disarmed on the way out: nothing is in flight once the host has
  // answered, and a timer left running would stop an idle run rather than a
  // late one.
  async _publish(entry) {
    if (this._loop.stopped || !this._worker) {
      throw new Error("no module is running")
    }
    this._arm()
    try {
      const results = await this.pushEventTo(this.el, "app-publish", {
        entry: toBase64(encode(entry))
      })
      const first = results && results[0]
      if (!first || first.status !== "fulfilled" || !first.value) {
        throw new Error("the app view did not answer")
      }
      const reply = first.value.reply
      this._record("publish", publishShape(reply))
      return reply
    } finally {
      this._disarm()
    }
  },

  // One entry of the run's own history. Batching keeps a module that prints
  // in a loop from turning into one socket message per line: the trace is a
  // list to read back, not a log tail that has to be live. Only panes that
  // asked for a trace get one — a published app's pane has nowhere to show
  // it and would only be pushing state nobody reads.
  _record(kind, detail) {
    if (!this.el.dataset.trace) return
    if (this._trace.length >= TRACE_LIMIT) this._trace.shift()
    this._trace.push({kind, detail: String(detail).slice(0, TRACE_DETAIL_LIMIT)})
    if (this._traceTimer !== null) return
    this._traceTimer = setTimeout(() => this._flushTrace(), TRACE_FLUSH_MS)
  },

  _flushTrace() {
    this._traceTimer = null
    if (this._trace.length === 0) return
    const entries = this._trace
    this._trace = []
    this.pushEvent("app-trace", {entries})
  },

  _arm() {
    this._disarm()
    this._timer = setTimeout(() => this._loop.stop("the app took too long"), DEADLINE_MS)
  },

  _disarm() {
    if (this._timer !== null) clearTimeout(this._timer)
    this._timer = null
  },

  _teardown() {
    this._disarm()
    this._stopAnimate()
    if (this._worker) this._worker.terminate()
    this._worker = null
  },

  // `{"do":"animate"}` turns the pane's frame clock on; `on: false` turns
  // it off. Each frame delivers one `{"msg":"tick","t":…}` — and only when
  // the previous delivery has been answered, so a module that takes 100 ms
  // a frame ticks ten a second rather than building a queue of sixteen
  // millisecond promises it has not kept. Skipping the frame *is* the
  // budget: the deadline armed in `_deliver` is what stops a module that
  // never answers at all.
  _startAnimate() {
    if (this._animateOn) return
    this._animateOn = true
    const frame = time => {
      if (!this._animateOn) return
      if (!this._inFlight && this._worker && this._loop && !this._loop.stopped) {
        this._deliver({msg: "tick", t: time})
      }
      this._raf = requestAnimationFrame(frame)
    }
    this._raf = requestAnimationFrame(frame)
  },

  _stopAnimate() {
    this._animateOn = false
    if (this._raf !== null) cancelAnimationFrame(this._raf)
    this._raf = null
  },

  // Pointer events over the view's canvas, delegated from the pane. The
  // coordinates are the module's own — canvas pixels, origin at its top
  // left — because the module owns the geometry and does the hit-testing
  // (§3). A capture on the way down keeps the matching `up` arriving even
  // when the pointer leaves the region mid-drag.
  _pointer(event) {
    const target = event.target
    if (!(target instanceof Element)) return
    const canvas = target.closest("canvas[data-app-canvas]")
    if (!canvas) return

    const type = {pointerdown: "down", pointermove: "move", pointerup: "up"}[event.type]
    if (!type) return

    if (type === "down") {
      try {
        canvas.setPointerCapture(event.pointerId)
      } catch (_) {
        // A capture is a convenience; without one the `up` simply does
        // not arrive if the pointer has left, which is the old behaviour.
      }
    }

    const entry = {type, x: Math.round(event.offsetX), y: Math.round(event.offsetY)}
    if (type !== "move") entry.button = event.button
    this._queueUi(entry)
  },

  // One message to the module at a time, newest sample wins for a move.
  _queueUi(entry) {
    const last = this._ui[this._ui.length - 1]
    if (entry.type === "move" && last && last.type === "move") {
      this._ui[this._ui.length - 1] = entry
    } else {
      this._ui.push(entry)
    }
    if (this._ui.length > UI_QUEUE_LIMIT) this._ui.shift()
    this._flushUi()
  },

  _flushUi() {
    if (this._inFlight || this._ui.length === 0) return
    if (!this._worker || !this._loop || this._loop.stopped) {
      this._ui = []
      return
    }
    this._deliver({msg: "ui", event: this._ui.shift()})
  }
}

function appendPrint(current, text) {
  const next = current ? `${current}\n${text}` : text
  return next.length > PRINT_LIMIT ? next.slice(next.length - PRINT_LIMIT) : next
}

// The wasm header: a NUL, then "asm", then a format version that is at least
// another four bytes. Checked before a drop-in is spawned so a text file
// dropped by mistake is a message in the pane rather than a link error out
// of the worker.
function isWasm(bytes) {
  return (
    bytes.length >= 8 &&
    bytes[0] === 0x00 &&
    bytes[1] === 0x61 &&
    bytes[2] === 0x73 &&
    bytes[3] === 0x6d
  )
}

function viewShape(value) {
  if (value === null || typeof value !== "object") return "value"
  if (typeof value.t === "string") return value.t
  if (typeof value.text === "string") return "text dump"
  return "value"
}

function replyShape(message) {
  if (!message) return "nothing"
  if (message.msg === "err") return `err ${message.error}`
  return `data #${message.ref}`
}

// One publish reads in the trace as what it wrote and where: the seqnum the
// store gave it, or the reason the host would not.
function publishShape(reply) {
  if (!reply || reply.ok !== true) {
    return `refused (${(reply && reply.error) || "no reason given"})`
  }
  return typeof reply.seq === "number" ? `ok, seq ${reply.seq}` : "ok"
}

function toBase64(bytes) {
  let binary = ""
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000))
  }
  return btoa(binary)
}
