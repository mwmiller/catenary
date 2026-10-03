rt = Catenary.Apps.DSL.Runtime

# The same prologue the compiler will emit for `handle`, minus dispatch:
# reset the turn, decode whatever the host sent, emit the effect list.
module = """
(module
  (memory (export "memory") 1)
#{rt.source()}
#{rt.data()}
  (func (export "handle") (param $in i32) (param $len i32) (result i32)
    (global.set $vp (i32.and (i32.add (i32.add (local.get $in) (local.get $len)) (i32.const 7)) (i32.const -8)))
    (global.set $ec (i32.const 4096))
    (global.set $ep (i32.const 0))
    (global.set $err (i32.const 0))
    (global.set $sc (i32.const 0))
    (global.set $scb (i32.const 0))
    (global.set $scc (i32.const 0))
    (global.set $dp (local.get $in))
    (global.set $de (i32.add (local.get $in) (local.get $len)))
    (drop (call $cbor_val (i32.const 0)))
    (call $finish))
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
