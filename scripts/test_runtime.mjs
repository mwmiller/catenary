// Behavioral checks for lib/catenary/apps/dsl/runtime.ex: decode -> show
// -> encode round-trips, and the comparison / lookup primitives, all
// verified against the JS end of the ABI (cbor.js) as the reference.
//
//   mix run --no-start scripts/test_runtime.exs   # build the wasm
//   node scripts/test_runtime.mjs                 # run this

import { readFile } from "node:fs/promises"

const { encode, decode } = await import(
  new URL("../assets/js/cbor.js", import.meta.url)
)

const wasmPath = process.argv[2] ?? "/tmp/runtime-test.wasm"
const wasm = await readFile(wasmPath)
const { instance } = await WebAssembly.instantiate(wasm, {})
const E = instance.exports

const INPUT = 0x1000
const ENC = 0xc000
const text = new TextDecoder()

let passes = 0
let fails = 0

function ok(desc, cond, extra) {
  if (cond) {
    passes++
  } else {
    fails++
    console.log(`FAIL ${desc}${extra !== undefined ? " :: " + show0(extra) : ""}`)
  }
}
function show0(v) {
  try {
    return JSON.stringify(v, (_, x) =>
      typeof x === "number" && Object.is(x, -0) ? "-0" :
      typeof x === "number" && Number.isNaN(x) ? "NaN" :
      typeof x === "bigint" ? String(x) : x
    ) ?? String(v)
  } catch { return String(v) }
}

function deq(a, b) {
  if (typeof a === "number" && typeof b === "number") return Object.is(a, b)
  if (Array.isArray(a) && Array.isArray(b))
    return a.length === b.length && a.every((x, i) => deq(x, b[i]))
  if (a instanceof Map && b instanceof Map) {
    if (a.size !== b.size) return false
    for (const [k, v] of a) if (!b.has(k) || !deq(v, b.get(k))) return false
    return true
  }
  if (a instanceof Uint8Array && b instanceof Uint8Array)
    return a.length === b.length && a.every((x, i) => x === b[i])
  const plain = v => v !== null && typeof v === "object" &&
    Object.getPrototypeOf(v) === Object.prototype
  if (plain(a) && plain(b)) {
    const ka = Object.keys(a), kb = Object.keys(b)
    return ka.length === kb.length &&
      ka.every(k => Object.prototype.hasOwnProperty.call(b, k) && deq(a[k], b[k]))
  }
  return a === b
}

const mem = () => new Uint8Array(E.memory.buffer)
const dv = () => new DataView(E.memory.buffer)

function boxRaw(bytes) {
  const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes)
  mem().set(u8, INPUT)
  return E.t_dec(INPUT, u8.length)
}
function box(value) {
  return boxRaw(encode(value))
}
function show(v) {
  const p = E.t_show(v)
  const n = dv().getUint32(p + 4, true)
  return text.decode(mem().slice(p + 8, p + 8 + n))
}
function encOf(v) {
  const end = E.t_enc(v)
  return decode(mem().slice(ENC, end))
}
function boxShow(value) {
  E.t_reset()
  return show(box(value))
}
function boxEnc(value) {
  E.t_reset()
  return encOf(box(value))
}

// --- round-trips ---------------------------------------------------------

function rt(desc, value) {
  E.t_reset()
  const input = encode(value)
  const expected = decode(input)
  const got = encOf(boxRaw(input))
  ok(`rt ${desc}`, deq(got, expected), { want: expected, got })
}
function rtRaw(desc, bytes) {
  E.t_reset()
  const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes)
  const expected = decode(u8)
  const got = encOf(boxRaw(u8))
  ok(`rt raw ${desc}`, deq(got, expected), { want: expected, got })
}

for (const n of [
  0, 1, 2, 23, 24, 25, 255, 256, 65535, 65536, 4294967295, 4294967296,
  9007199254740991, 9007199254740992,
  -1, -24, -25, -255, -256, -65536, -4294967296, -9007199254740992,
]) rt(`int ${n}`, n)

for (const f of [1.5, -2.25, 0.1, 0.3333333333333333, -0.0009765625, 1e10, 1e-10, 1234567890.125])
  rt(`float ${f}`, f)

rt("NaN", NaN)
rt("inf", Infinity)
rt("-inf", -Infinity)
rtRaw("-0", [0xfb, 0x80, 0, 0, 0, 0, 0, 0, 0])
rtRaw("f16 inf", [0xf9, 0x7c, 0x00])
rtRaw("f16 -inf", [0xf9, 0xfc, 0x00])
rtRaw("f16 nan", [0xf9, 0x7e, 0x00])
rtRaw("f16 -nan", [0xf9, 0x7f, 0xff])
rtRaw("f16 1", [0xf9, 0x3c, 0x00])
rtRaw("f16 -1", [0xf9, 0xc4, 0x00])
rtRaw("f16 subnormal 2^-24", [0xf9, 0x00, 0x01])
rtRaw("f16 65504", [0xf9, 0x7b, 0xff])
rtRaw("f64 -0", [0xfb, 0x80, 0, 0, 0, 0, 0, 0, 0])

rt("bool true", true)
rt("bool false", false)
rt("null", null)
rt("empty text", "")
rt("ascii", "hello")
rt("unicode", "héllo 🎉 日本語")
rt("empty bytes", new Uint8Array(0))
rt("bytes", new Uint8Array([0, 1, 2, 254, 255]))
rt("empty array", [])
rt("array", [1, "a", null, true, [2, [3]]])
rt("empty object", {})
rt("object", { a: 1, b: "two", c: [3], d: { e: null } })
rt("map int keys", new Map([[1, "x"], [2, "y"]]))
rt("mixed", { n: 1.5, s: "txt", b: new Uint8Array([9]), l: [1, [2, [3, [4]]]], m: { x: { y: [] } } })
rt("20 deep", JSON.parse('[[[[[[[[[[[[[[[[[[[[1]]]]]]]]]]]]]]]]]]]]'))

// --- show ---------------------------------------------------------------

function shows(desc, value, expected) {
  const got = boxShow(value)
  ok(`show ${desc}`, got === expected, { want: expected, got })
}

shows("null", null, "null")
shows("true", true, "true")
shows("false", false, "false")
shows("int", 42, "42")
shows("neg int", -7, "-7")
shows("zero", 0, "0")
shows("neg zero", -0, "0")
shows("big int", 9007199254740992, "9007199254740992")
shows("huge", 1e21, "1000000000000000000000")
shows("1.5", 1.5, "1.5")
shows("0.1", 0.1, "0.1")
shows("third", 0.3333333333333333, "0.333333333333333")
shows("two thirds", 0.6666666666666666, "0.666666666666666")
shows("nan", NaN, "nan")
shows("inf", Infinity, "inf")
shows("-inf", -Infinity, "-inf")
shows("small", 0.0000001, "0.0000001")
shows("text top", "hi", "hi")
shows("text nested", ["hi"], '["hi"]')
shows("array", [1, "a", null, true], '[1,"a",null,true]')
shows("empty array", [], "[]")
shows("empty object", {}, "{}")
shows("object", { a: 1 }, '{"a":1}')
shows("object int key", { 1: "x" }, '{"1":"x"}')
shows("map int key", new Map([[1, "x"]]), '{1:"x"}')
shows("nested object", { a: { b: [1] } }, '{"a":{"b":[1]}}')
shows("bytes", new Uint8Array([1, 2, 255]), "0x0102ff")
shows("depth cut", JSON.parse('[[[[[1]]]]]'), "[[[[[...]]]]]")
shows(
  "16 elem cut",
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
  "[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,..]"
)
{
  const long = "x".repeat(3001)
  shows("3000 cap", [long], '["' + "x".repeat(2998) + "…")
}

// --- truthy --------------------------------------------------------------

function truthyCase(value, expected) {
  E.t_reset()
  const got = E.t_truthy(box(value)) !== 0
  ok(`truthy ${show0(value)}`, got === expected, { want: expected, got })
}
truthyCase(0, false)
truthyCase(1, true)
truthyCase(-1, true)
truthyCase(NaN, false)
truthyCase("", false)
truthyCase("x", true)
truthyCase([], true)
truthyCase({}, true)
truthyCase(new Uint8Array(0), false)
truthyCase(new Uint8Array([1]), true)
truthyCase(null, false)
truthyCase(false, false)
truthyCase(true, true)

// --- equality ------------------------------------------------------------

function eqCase(a, b, expected) {
  E.t_reset()
  const got = E.t_eq(box(a), box(b)) !== 0
  ok(`eq ${show0(a)} / ${show0(b)}`, got === expected, { want: expected, got })
}
eqCase(1, 1, true)
eqCase(1, 1.0, true)
eqCase(1, 2, false)
eqCase(NaN, NaN, false)
eqCase(-0, 0, true)
eqCase(null, null, true)
eqCase(null, false, false)
eqCase(true, true, true)
eqCase(true, false, false)
eqCase("a", "a", true)
eqCase("a", "b", false)
eqCase("1", 1, false)
eqCase("ab", new Uint8Array([0x61, 0x62]), false)
eqCase(new Uint8Array([1, 2]), new Uint8Array([1, 2]), true)
eqCase([1, [2]], [1, [2]], true)
eqCase([1], [2], false)
eqCase({ a: [1] }, { a: [1] }, true)
eqCase({ a: 1 }, { a: 1, b: 2 }, false)
eqCase({ 1: "x" }, { 1: "x" }, true)

// --- order ---------------------------------------------------------------

function cmpCase(name, fn, a, b, expected) {
  E.t_reset()
  const r = fn(box(a), box(b))
  const got = encOf(r)
  ok(name, deq(got, expected), { want: expected, got })
}
function ltCase(a, b, expected) { cmpCase(`lt ${show0(a)} ${show0(b)}`, E.t_lt, a, b, expected) }
function leCase(a, b, expected) { cmpCase(`le ${show0(a)} ${show0(b)}`, E.t_le, a, b, expected) }

ltCase(1, 2, true)
ltCase(2, 1, false)
ltCase(1, 1, false)
ltCase(1.5, 1.5, false)
ltCase(NaN, 1, false)
ltCase("a", "b", true)
ltCase("ab", "b", true)
ltCase("a", "ab", true)
ltCase("ab", "a", false)
ltCase("a", "a", false)
ltCase("b", "ab", false)
ltCase(1, "a", false)
ltCase(null, null, false)
ltCase(true, false, false)
ltCase([], [], false)

leCase(1, 1, true)
leCase(2, 1, false)
leCase("a", "a", true)
leCase("ab", "a", false)
leCase(1, 2, true)
leCase(null, null, false)

// --- add -----------------------------------------------------------------

function addCase(a, b, expected) {
  E.t_reset()
  const got = encOf(E.t_add(box(a), box(b)))
  ok(`add ${show0(a)} ${show0(b)}`, deq(got, expected), { want: expected, got })
}
addCase(1, 2, 3)
addCase(1.5, 2, 3.5)
addCase(-3, 3, 0)
addCase("a", "b", "ab")
addCase(1, "a", "1a")
addCase("a", 1, "a1")
addCase(true, 1, NaN)
addCase([1], [2], NaN)

// --- len -----------------------------------------------------------------

function lenCase(value, expected) {
  E.t_reset()
  const got = encOf(E.t_len(box(value)))
  ok(`len ${show0(value)}`, deq(got, expected), { want: expected, got })
}
lenCase("abc", 3)
lenCase("🎉", 4)
lenCase("", 0)
lenCase([], 0)
lenCase([1, 2], 2)
lenCase({}, 0)
lenCase({ a: 1, b: 2 }, 2)
lenCase(new Uint8Array([0, 1]), 2)
lenCase(5, NaN)
lenCase(null, NaN)

// --- field / index -------------------------------------------------------

function fieldCase(map, key, expected) {
  E.t_reset()
  const got = encOf(E.t_field(box(map), box(key)))
  ok(`field ${show0(map)}[${show0(key)}]`, deq(got, expected), { want: expected, got })
}
fieldCase({ a: 1 }, "a", 1)
fieldCase({ a: 1 }, "b", null)
fieldCase({ "a": null }, "a", null)
fieldCase(new Map([[1, "x"]]), 1, "x")
fieldCase([1, 2], "a", null)
fieldCase({ ab: 3 }, "a", null)

function indexCase(arr, idx, expected) {
  E.t_reset()
  const got = encOf(E.t_index(box(arr), box(idx)))
  ok(`index ${show0(arr)}[${show0(idx)}]`, deq(got, expected), { want: expected, got })
}
indexCase([10, 20], 1, 20)
indexCase([10, 20], 0, 10)
indexCase([10, 20], 1.0, 20)
indexCase([10, 20], 2, null)
indexCase([10, 20], -1, null)
indexCase([10, 20], 1.5, null)
indexCase([10, 20], "x", null)
indexCase([10, 20], 9007199254740993, null)
indexCase([], 0, null)
indexCase("abc", 0, null)
indexCase({ a: 1 }, "a", null)

// --- decode never traps --------------------------------------------------

E.t_reset()
const garbage = new Uint8Array([0xff, 0xff, 0xff, 0xff, 0xff])
mem().set(garbage, INPUT)
E.t_dec(INPUT, garbage.length)
ok("garbage decodes without trapping", true)

console.log(`${passes} passed, ${fails} failed`)
process.exit(fails ? 1 : 0)
