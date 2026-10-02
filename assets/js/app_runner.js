// The `AppRunner` hook: everything that ties a module to the page.
//
// It owns the worker (the kill switch), the two sinks the component
// renders into, and the round trips to the host. The effect semantics live
// in `app_loop.js` and the memory protocol in `app_session.js`; this file
// is only the wiring between them and LiveView.
//
// One deadline covers every wait — the module loading, it starting (which
// includes its own `start` code), a `handle` that never returns, and a host
// reply that never arrives. Any of those is a reason to terminate the
// worker, which is also the only way to stop a module that is spinning.

import {AppLoop, isMap} from "./app_loop.js"
import {buildView} from "./app_view.js"
import {encode} from "./cbor.js"
const DEADLINE_MS = 5000
const PRINT_LIMIT = 64 * 1024

export const AppRunner = {
  mounted() {
    const status = this.el.querySelector("#app-status")
    const print = this.el.querySelector("#app-print")
    const view = this.el.querySelector("#app-view")

    this._worker = null
    this._timer = null

    this._loop = new AppLoop({
      status: text => {
        status.textContent = text
      },
      stop: () => this._teardown(),
      print: text => {
        print.textContent = appendPrint(print.textContent, text)
        print.classList.remove("hidden")
      },
      render: value => {
        // A tree that failed validation comes back with `strike`, and as
        // the text dump rather than as a half-built view.
        const built = buildView(value)
        if (built.strike) this._loop.strike(built.strike)
        view.textContent = ""
        view.appendChild(built.node)
        view.classList.remove("hidden")
      },
      want: (op, args) => this._want(op, args),
      deliver: message => this._deliver(message)
    })

    const src = this.el.dataset.wasmSrc
    if (src) this._load(src)
  },

  destroyed() {
    this._teardown()
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
    this._worker.postMessage({type: "start", wasm}, [wasm])
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

function toBase64(bytes) {
  let binary = ""
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000))
  }
  return btoa(binary)
}
