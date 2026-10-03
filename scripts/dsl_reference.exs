rt = Catenary.Apps.DSL.Runtime

# The executable spec for DSL codegen: the hand-written target for
# `on init: print("hello from dsl")`. The compiler's output must instantiate
# and behave identically under scripts/dsl-harness.mjs.
#
# Pool layout from 112 (8-aligned data boxes):
#   112 "msg"   128 "init"   144 "do"   160 "print"   176 "text"   192 "hello from dsl"
module = """
(module
  (memory (export "memory") 1)
#{rt.source()}
#{rt.data()}
  (data (i32.const 112) "\\04\\00\\00\\00\\03\\00\\00\\00msg")
  (data (i32.const 128) "\\04\\00\\00\\00\\04\\00\\00\\00init")
  (data (i32.const 144) "\\04\\00\\00\\00\\02\\00\\00\\00do")
  (data (i32.const 160) "\\04\\00\\00\\00\\05\\00\\00\\00print")
  (data (i32.const 176) "\\04\\00\\00\\00\\04\\00\\00\\00text")
  (data (i32.const 192) "\\04\\00\\00\\00\\0e\\00\\00\\00hello from dsl")
  (func $h_init
    (local $e i32)
    (local.set $e (call $map_new (i32.const 2)))
    (call $map_set (local.get $e) (i32.const 0) (i32.const 144) (i32.const 160))
    (call $map_set (local.get $e) (i32.const 1) (i32.const 176) (i32.const 192))
    (call $elist_push (local.get $e)))
  (func (export "handle") (param $in i32) (param $len i32) (result i32)
    (local $m i32)
    (global.set $vp (i32.and (i32.add (i32.add (local.get $in) (local.get $len)) (i32.const 7)) (i32.const -8)))
    (global.set $ec (i32.const 4096))
    (global.set $ep (i32.const 0))
    (global.set $err (i32.const 0))
    (global.set $sc (i32.const 0))
    (global.set $scb (i32.const 0))
    (global.set $scc (i32.const 0))
    (global.set $dp (local.get $in))
    (global.set $de (i32.add (local.get $in) (local.get $len)))
    (local.set $m (call $cbor_val (i32.const 0)))
    (if (call $v_text_eq (call $v_field (local.get $m) (i32.const 112)) (i32.const 128))
      (then (call $h_init)))
    (call $finish))
)
"""

try do
  wasm = Watusi.to_wasm(module)
  File.write!("/tmp/dsl-ref.wasm", wasm)
  IO.puts("OK #{byte_size(wasm)} bytes -> /tmp/dsl-ref.wasm")
rescue
  e ->
    IO.puts("FAIL: #{Exception.message(e)}")

    Enum.take(__STACKTRACE__, 6)
    |> Enum.each(fn {m, f, a, loc} ->
      IO.puts("  #{inspect(m)}.#{f}/#{length(a)} #{inspect(loc)}")
    end)
end
