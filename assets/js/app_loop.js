// The main-thread half of the loop: take the effects a module produced and
// act on them.
//
// Nothing here knows about the DOM or about LiveView — every effect is
// handed to a sink, which is what makes the loop drivable from anywhere and
// keeps the ordering rules in one place:
//
//   * effects are acted on in the order they were produced;
//   * a `want` is answered before the next one starts, so replies come back
//     in the order the module asked for them;
//   * a `want` that cannot be answered is answered with the ABI's `err`
//     message instead of being dropped, so the module is never left waiting
//     on a reply that will not come, and can observe the refusal;
//   * everything the module can be told about is a strike rather than a
//     stop — a refusal, an unreadable or malformed effect — and
//     STRIKE_LIMIT strikes stop the app. Failures that leave nothing left
//     to tell (the module did not load, the worker died, the deadline
//     expired, a reply could not be delivered) still stop it at once.

import {decode} from "./cbor.js"

// How many recoverable violations a run tolerates. The limit is what turns
// a module that refuses everything it asks for, or emits junk it cannot be
// handed back, from a slow stall into a stop with a reason.
export const STRIKE_LIMIT = 5

export class AppLoop {
  constructor(sinks) {
    this.sinks = sinks
    this.stopped = false
    this.strikes = 0
  }

  // Stop the app: the reason becomes the status line, and the sink tears
  // the worker down. Calling it twice does nothing, so a failure during a
  // teardown is not a second failure.
  stop(reason) {
    if (this.stopped) return
    this.stopped = true
    this.sinks.status(reason)
    this.sinks.stop(reason)
  }

  // Count one recoverable violation, from a bad effect or from a sink
  // that could not use what a module sent. Returns true when the app is
  // over, so callers can `if (this.strike(reason)) return`.
  strike(reason) {
    if (this.stopped) return true

    this.strikes += 1
    if (this.strikes >= STRIKE_LIMIT) {
      this.stop(`${reason} — ${STRIKE_LIMIT} strikes, app stopped`)
      return true
    }

    // The status line carries the count; the print log carries what it was,
    // because that is where a module's own output already goes and where a
    // reader is already looking.
    this.sinks.status(`running — ${this.strikes} of ${STRIKE_LIMIT} strikes`)
    this.sinks.print(`strike: ${reason}`)
    return false
  }

  // Effect arrays are handled one at a time in the order they arrive, so
  // two deliveries can never interleave their prints or their replies.
  effects(bytes) {
    const previous = this._queue || Promise.resolve()
    this._queue = previous
      .then(() => this.#run(bytes))
      .catch(error => this.stop(`the effects could not be applied (${error.message})`))
    return this._queue
  }

  async #run(bytes) {
    if (this.stopped) return

    let effects
    try {
      effects = decode(bytes)
    } catch (error) {
      // Nothing in the array can be applied, so the whole delivery is one
      // strike rather than one per effect.
      return this.strike(`the module produced unreadable effects (${error.message})`)
    }

    if (!Array.isArray(effects)) {
      return this.strike("the module produced effects that are not a list")
    }

    const wants = []
    for (const effect of effects) {
      if (this.stopped) return
      if (effect === null || typeof effect !== "object" || Array.isArray(effect)) {
        this.strike("the module produced an effect that is not a map")
        continue
      }
      switch (effect.do) {
        case "print":
          this.sinks.print(asText(effect.text))
          break
        case "render":
          this.sinks.render(effect.view)
          break
        case "want":
          wants.push(effect)
          break
        default:
          this.strike(`unsupported effect: ${asText(effect.do)}`)
      }
    }

    for (const want of wants) {
      await this.#fulfill(want)
      if (this.stopped) return
    }
  }

  async #fulfill(want) {
    const {ref, op} = want
    const knownRef = Number.isSafeInteger(ref) && ref >= 0

    if (typeof op !== "string") {
      return this.#refuse(ref, "a want did not name an operation")
    }
    // The reply comes back as {"msg":"data"|"err","ref":...}, so a `want`
    // that cannot be matched would reach the module as CBOR null —
    // indistinguishable from a real reference. Ref is therefore required;
    // without one there is no way to tell the module what happened.
    if (!knownRef) {
      return this.strike("a want did not carry a reference number")
    }
    if (want.args !== undefined && !isMap(want.args)) {
      return this.#refuse(ref, `the arguments for ${op} are not a map`)
    }

    let reply
    try {
      reply = await this.sinks.want(op, want.args ?? {})
    } catch (error) {
      return this.#refuse(ref, `the host could not be reached (${error.message})`)
    }

    if (this.stopped) return
    if (!reply || reply.ok !== true) {
      const text = (reply && reply.error) || "no reason given"
      return this.#refuse(ref, text, `the host refused ${op}: ${text}`)
    }

    try {
      // `data` carries the host's CBOR as it came off the wire: a module
      // decodes it once, whether it was a payload, a plain value or a
      // structure built by an index.
      await this.sinks.deliver({msg: "data", ref, ok: fromBase64(reply.data)})
    } catch (error) {
      this.stop(`the reply could not be delivered (${error.message})`)
    }
  }

  // A `want` that gets no answer would leave the module waiting for a
  // reply that is not coming, so the refusal is handed back as the ABI's
  // `err` message and the round trip completes either way. A `ref` the
  // module cannot be matched against (it never sent one) is only a strike.
  async #refuse(ref, text, reason = text) {
    if (this.strike(reason)) return
    if (!Number.isSafeInteger(ref) || ref < 0) return

    try {
      await this.sinks.deliver({msg: "err", ref, error: text})
    } catch (error) {
      this.stop(`the refusal could not be delivered (${error.message})`)
    }
  }
}

export function isMap(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function asText(value) {
  if (typeof value === "string") return value
  if (value === null || value === undefined) return ""
  return String(value)
}

export function fromBase64(text) {
  const binary = atob(text)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes
}
