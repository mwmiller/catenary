rt = Catenary.Apps.DSL.Runtime

# The runtime plus the narrow test surface scripts/test_runtime.mjs drives:
# decode a CBOR value, show it, encode it back, and poke the comparison and
# lookup primitives directly. The compiler's own codegen never sees this —
# it is the executable check on runtime.ex itself.
module = """
(module
  (memory (export "memory") 1)
#{rt.source()}
#{rt.data()}
  (func (export "t_reset")
    (global.set $vp (i32.const 36864))
    (global.set $ec (i32.const 4096))
    (global.set $err (i32.const 0))
    (global.set $sc (i32.const 0))
    (global.set $scb (i32.const 0))
    (global.set $scc (i32.const 0)))
  (func (export "t_dec") (param $p i32) (param $n i32) (result i32)
    (global.set $err (i32.const 0))
    (global.set $dp (local.get $p))
    (global.set $de (i32.add (local.get $p) (local.get $n)))
    (call $cbor_val (i32.const 0)))
  (func (export "t_enc") (param $v i32) (result i32)
    (global.set $ep (i32.const 49152))
    (call $enc_val (local.get $v))
    (global.get $ep))
  (func (export "t_show") (param $v i32) (result i32) (call $v_show (local.get $v)))
  (func (export "t_tag") (param $v i32) (result i32) (call $v_tag (local.get $v)))
  (func (export "t_truthy") (param $v i32) (result i32) (call $truthy (local.get $v)))
  (func (export "t_eq") (param $a i32) (param $b i32) (result i32) (call $v_eq (local.get $a) (local.get $b)))
  (func (export "t_lt") (param $a i32) (param $b i32) (result i32) (call $v_lt (local.get $a) (local.get $b)))
  (func (export "t_le") (param $a i32) (param $b i32) (result i32) (call $v_le (local.get $a) (local.get $b)))
  (func (export "t_add") (param $a i32) (param $b i32) (result i32) (call $v_add (local.get $a) (local.get $b)))
  (func (export "t_len") (param $v i32) (result i32) (call $v_len (local.get $v)))
  (func (export "t_field") (param $m i32) (param $k i32) (result i32) (call $v_field (local.get $m) (local.get $k)))
  (func (export "t_index") (param $a i32) (param $i i32) (result i32) (call $v_index (local.get $a) (local.get $i)))
)
"""

try do
  wasm = Watusi.to_wasm(module)
  File.write!("/tmp/runtime-test.wasm", wasm)
  IO.puts("OK #{byte_size(wasm)} bytes -> /tmp/runtime-test.wasm")
rescue
  e ->
    IO.puts("FAIL: #{Exception.message(e)}")
    Enum.take(__STACKTRACE__, 6)
    |> Enum.each(fn {m, f, a, loc} ->
      IO.puts("  #{inspect(m)}.#{f}/#{length(a)} #{inspect(loc)}")
    end)
end
