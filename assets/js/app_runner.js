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

import {AppLoop, fromBase64, isMap} from "./app_loop.js"
import {buildView} from "./app_view.js"
import {encode} from "./cbor.js"
const DEADLINE_MS = 5000
const PRINT_LIMIT = 64 * 1024
const TRACE_LIMIT = 200
const TRACE_DETAIL_LIMIT = 400
const TRACE_FLUSH_MS = 120

export const AppRunner = {
  mounted() {
    this._worker = null
    this._timer = null
    this._trace = []
    this._traceTimer = null
    this._loop = this._newLoop()

    this.handleEvent("app-run", payload => this._run(payload || {}))
    this.handleEvent("app-stop", () => this._loop.stop("stopped"))

    const src = this.el.dataset.wasmSrc
    if (src) this._load(src)
  },

  destroyed() {
    if (this._traceTimer !== null) clearTimeout(this._traceTimer)
    this._traceTimer = null
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
        this._record("stop", reason)
        this._teardown()
      },
      print: text => {
        this._record("print", text)
        print.textContent = appendPrint(print.textContent, text)
        print.classList.remove("hidden")
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
      want: (op, args) => {
        this._record("want", op)
        return this._want(op, args)
      },
      deliver: message => {
        this._record("reply", replyShape(message))
        return this._deliver(message)
      }
    })
  },

  // Start a run. Either the payload carries the module (`wasm`, already
  // compiled by the host) or a URL to fetch it from; an `error` means the
  // host could not produce a module at all, which is a status line rather
  // than a failure of the pane.
  _run(payload) {
    this._teardown()
    if (this._traceTimer !== null) clearTimeout(this._traceTimer)
    this._traceTimer = null
    this._trace = []

    const status = this.el.querySelector("#app-status")
    const print = this.el.querySelector("#app-print")
    const view = this.el.querySelector("#app-view")
    print.textContent = ""
    print.classList.add("hidden")
    view.textContent = ""
    view.classList.add("hidden")

    this._loop = this._newLoop()

    if (payload.error) {
      status.textContent = `could not compile (${payload.error})`
      return
    }

    status.textContent = "starting…"
    if (payload.wasm) this._spawn(fromBase64(payload.wasm))
    else if (payload.src) this._load(payload.src)
    else status.textContent = "nothing to run"
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

  _onWorker(message) {
    if (!message) return
    switch (message.type) {
      case "ready":
        this._disarm()
        this._loop.sinks.status("running")
        this._deliver({msg: "init"})
        break
      case "effects":
        this._disarm()
        this._loop.effects(message.bytes)
        break
      case "error":
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
    if (this._worker) this._worker.terminate()
    this._worker = null
  }
}

function appendPrint(current, text) {
  const next = current ? `${current}\n${text}` : text
  return next.length > PRINT_LIMIT ? next.slice(next.length - PRINT_LIMIT) : next
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

function toBase64(bytes) {
  let binary = ""
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000))
  }
  return btoa(binary)
}
