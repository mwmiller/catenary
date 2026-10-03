#!/usr/bin/env node
// Drive a DSL-generated wasm module through the message ABI exactly the way
// app_session/app_runner does: write the CBOR message at 0x1000, call
// handle, read the length slot at 0, decode the effects. The reference
// module (scripts/dsl_reference.exs) passes; the compiler's output must
// pass the same scenarios.
//
//   mix run --no-start scripts/dsl_reference.exs
//   node scripts/dsl-harness.mjs /tmp/dsl-ref.wasm

import { readFileSync } from "node:fs"
import { encode, decode } from "../assets/js/cbor.js"

const wasmPath = process.argv[2]
if (!wasmPath) {
  console.error("usage: node scripts/dsl-harness.mjs <module.wasm>")
  process.exit(2)
}

const wasm = readFileSync(wasmPath)
const { instance } = await WebAssembly.instantiate(wasm, {})
const { memory, handle } = instance.exports
if (!(memory instanceof WebAssembly.Memory)) {
  console.error("FAIL: module does not export memory")
  process.exit(1)
}
if (typeof handle !== "function") {
  console.error("FAIL: module does not export handle")
  process.exit(1)
}

const INPUT = 0x1000

function step(message) {
  const bytes = encode(message)
  if (INPUT + bytes.length > memory.buffer.byteLength) {
    memory.grow(
      Math.ceil((INPUT + bytes.length - memory.buffer.byteLength) / 65536)
    )
  }
  new Uint8Array(memory.buffer).set(bytes, INPUT)
  const outPtr = handle(INPUT, bytes.length) >>> 0
  const length = new DataView(memory.buffer, 0, 4).getUint32(0, true)
  if (outPtr + length > memory.buffer.byteLength) {
    throw new Error("module returned a result outside its memory")
  }
  return decode(new Uint8Array(memory.buffer).slice(outPtr, outPtr + length))
}

function show0(v) {
  try {
    return (
      JSON.stringify(v, (_, x) =>
        typeof x === "number" && Object.is(x, -0) ? "-0" :
        typeof x === "number" && Number.isNaN(x) ? "NaN" : x
      ) ?? String(v)
    )
  } catch {
    return String(v)
  }
}

function deq(a, b) {
  if (typeof a === "number" && typeof b === "number") return Object.is(a, b)
  if (Array.isArray(a) && Array.isArray(b))
    return a.length === b.length && a.every((x, i) => deq(x, b[i]))
  if (a instanceof Uint8Array && b instanceof Uint8Array)
    return a.length === b.length && a.every((x, i) => x === b[i])
  const plain = v =>
    v !== null && typeof v === "object" &&
    Object.getPrototypeOf(v) === Object.prototype
  if (plain(a) && plain(b)) {
    const ka = Object.keys(a), kb = Object.keys(b)
    return ka.length === kb.length &&
      ka.every(k => Object.prototype.hasOwnProperty.call(b, k) && deq(a[k], b[k]))
  }
  return a === b
}

let failed = 0
let passed = 0
function check(desc, got, want) {
  if (deq(got, want)) {
    passed++
  } else {
    failed++
    console.log(`FAIL ${desc} :: ${show0({ want, got })}`)
  }
}

// --- scenarios -------------------------------------------------------------

check(
  "init prints hello",
  step({ msg: "init" }),
  [{ do: "print", text: "hello from dsl" }]
)
check("tick silent", step({ msg: "tick", t: 0 }), [])
check("ui silent", step({ msg: "ui", event: { x: 1, y: 2 } }), [])
check("data silent", step({ msg: "data", ref: 1, ok: new Uint8Array([1]) }), [])
check("err silent", step({ msg: "err", ref: 1, error: "no" }), [])
check("garbage silent", step({ msg: "wat" }), [])
check("empty input silent", step([]), [])

console.log(`${passed} passed, ${failed} failed`)
process.exit(failed ? 1 : 0)
