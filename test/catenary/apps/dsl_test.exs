defmodule Catenary.Apps.DSLTest do
  use ExUnit.Case, async: true

  alias Catenary.Apps.DSL

  # Diagnostics are the product: positions land back in the editor pane
  # (§2), so most assertions here are exact strings, position included.

  defp compile_error(source) do
    assert {:error, message} = DSL.compile(source)
    message
  end

  defp compile_ok!(source) do
    assert {:ok, wat} = DSL.compile(source)
    wat
  end

  # ================================================================ lexing

  test "tabs are rejected with a position" do
    assert compile_error("on init:\n\tprint(1)\n") ==
             "line 2, col 1: tabs are not allowed; use spaces"
  end

  test "unterminated string" do
    assert compile_error("on init:\n  print(\"hi)\n") ==
             "line 2, col 1: unterminated string"
  end

  # ================================================================ parsing

  test "unknown handler header shows that handler's form" do
    source = ~S|on init:
  print(1)
on tick(t, t):
  print(1)
|

    assert compile_error(source) == "line 3, col 4: tick takes one parameter: on tick(name):"
  end

  test "data header needs a label and a name" do
    source = ~S|on init:
  print(1)
on data("l"):
  print(1)
|

    assert compile_error(source) ==
             ~s|line 3, col 4: data needs a label and a name: on data("label", name):|
  end

  test "unrecognized handler name" do
    source = ~S|on init:
  print(1)
on frob(x):
  print(1)
|

    assert compile_error(source) ==
             ~s|line 3, col 4: unknown handler; expected init, data("label", name), err(name), tick(name) or ui(name)|
  end

  test "unexpected indent inside a block" do
    assert compile_error("on init:\n  print(1)\n    print(2)\n") ==
             "line 3, col 5: unexpected indent"
  end

  test "dedented line at top level" do
    assert compile_error(~S|on init:
  print(1)
 print(2)
|) == "line 3, col 2: unexpected indent (handlers start at the top level)"
  end

  test "else without a matching if" do
    source = ~S|on init:
  else:
    print(1)
|

    assert compile_error(source) == "line 3, col 1: else without a matching if"
  end

  test "else must be a block, not an expression" do
    source = ~S|on init:
  let a = 1
  if a == 1:
    print("one")
  else if a == 2:
    print("two")
|

    assert compile_error(source) ==
             "line 3, col 1: else must be followed by : and an indented block"
  end

  test "match needs at least one arm" do
    source = ~S|on init:
  let y = 1
  match y:
    print(1)
|

    assert compile_error(source) == "line 4, col 5: expected when or else in match (saw print)"
  end

  test "want is a statement, not a value" do
    source = ~S|on data("l", r):
  print(want "l" = log_head(log_id: 1))
|

    assert compile_error(source) == "line 2, col 14: expected ), saw a string"
  end

  # ================================================================ scope

  test "unknown variable" do
    assert compile_error("on init:\n  print(x)\n") ==
             "line 2, col 9: x is not defined"
  end

  test "assignment requires a prior let" do
    assert compile_error("on init:\n  y = 1\n") ==
             "line 2, col 3: y is not defined (let y = … first)"
  end

  test "reserved word as a let name" do
    assert compile_error("on init:\n  let text = 1\n") ==
             "line 2, col 3: text is a reserved word"
  end

  test "reserved word as a handler parameter" do
    source = ~S|on init:
  print(1)
on tick(draw):
  print(1)
|

    assert compile_error(source) == "line 3, col 9: draw is a reserved word"
  end

  test "duplicate let in one handler" do
    source = ~S|on init:
  let x = 1
  let x = 2
|

    assert compile_error(source) == "line 3, col 3: x is already defined"
  end

  test "handler-local lets never leak between handlers" do
    wat =
      compile_ok!(~S|on init:
  let x = 1
  print(show(x))
on tick(t):
  let x = 2
  print(show(x))
|)

    # One local per handler, each declared inside its own function.
    assert length(String.split(wat, "(local $L_x i32)")) == 3
  end

  # ============================================================= handlers

  test "init is required" do
    assert compile_error("on tick(t):\n  print(1)\n") == "line 1, col 1: on init: is required"
    assert compile_error("") == "line 1, col 1: on init: is required"
    assert compile_error("# just a comment\n") == "line 1, col 1: on init: is required"
  end

  test "init may appear only once" do
    source = ~S|on init:
  print(1)
on init:
  print(2)
|

    assert compile_error(source) == "line 1, col 1: duplicate init handler"
  end

  test "one handler per message kind" do
    source = ~S|on init:
  print(1)
on tick(t):
  print(1)
on tick(t):
  print(2)
|

    assert compile_error(source) == "line 1, col 1: duplicate tick handler"
  end

  test "data labels are unique" do
    source = ~S|on init:
  print(1)
on data("l", r):
  print(1)
on data("l", r):
  print(2)
|

    assert compile_error(source) == ~s|line 5, col 9: duplicate data label "l"|
  end

  # ========================================================== expressions

  test "builtin arity is checked with a position" do
    assert compile_error("on init:\n  print(show(1, 2))\n") ==
             "line 2, col 9: show takes 1 argument(s), got 2"
  end

  test "unknown function" do
    assert compile_error("on init:\n  print(frob(1))\n") ==
             "line 2, col 9: unknown function frob"
  end

  test "host operations cannot appear in expressions" do
    source = ~S|on init:
  print(log_read(log_id: 1, seq: 1))
|

    assert compile_error(source) ==
             ~s|line 2, col 9: log_read is used inside want "label" = log_read(…)|
  end

  test "draw ops cannot appear in expressions" do
    source = ~S|on init:
  print(fill_rect(x: 1, y: 1, w: 1, h: 1))
|

    assert compile_error(source) == "line 2, col 9: fill_rect can only be used inside draw [...]"
  end

  test "when arms must be literals" do
    source = ~S|on init:
  let y = 1
  match y:
    when y:
      print(1)
|

    assert compile_error(source) == "line 4, col 10: when expects a literal value"
  end

  # ================================================================ views

  test "render takes a view, not a value" do
    assert compile_error("on init:\n  render(\"hi\")\n") ==
             "line 1, col 1: render expects a view (text, col, row or canvas)"
  end

  test "nested view nodes must be views" do
    assert compile_error("on init:\n  render(col(show(1)))\n") ==
             "line 1, col 1: render expects a view (text, col, row or canvas)"
  end

  test "text takes one argument" do
    source = ~S|on init:
  render(text("a", "b"))
|

    assert compile_error(source) == "line 2, col 10: text takes 1 argument(s), got 2"
  end

  test "nested view arity" do
    assert compile_error("on init:\n  render(canvas(64))\n") ==
             "line 2, col 10: canvas takes 2 argument(s), got 1"
  end

  # ================================================================= draw

  test "unknown draw op" do
    assert compile_error("on init:\n  draw[bogus(x: 1)]\n") ==
             "line 2, col 8: unknown draw op bogus"
  end

  test "draw op missing a required field" do
    assert compile_error("on init:\n  draw[fill_rect(x: 0)]\n") ==
             "line 2, col 8: fill_rect is missing y"
  end

  test "draw ops take named arguments" do
    assert compile_error("on init:\n  draw[fill_rect(1)]\n") ==
             "line 2, col 8: fill_rect takes named arguments (x: …, y: …, w: …, h: …)"
  end

  test "view builders cannot be drawn" do
    assert compile_error("on init:\n  draw[col(text(\"a\"))]\n") ==
             "line 2, col 8: col builds a view; it cannot be drawn (did you mean render?)"
  end

  # =========================================================== host / want

  test "want label must be a declared data label" do
    source = ~S|on init:
  want "nope" = log_head(log_id: 1)
|

    assert compile_error(source) ==
             ~s|line 2, col 3: unknown data label "nope" (declare on data("nope", …) first)|
  end

  test "unknown host operation" do
    source = ~S|on init:
  print(1)
on data("l", r):
  want "l" = frobnicate(a: 1)
|

    assert compile_error(source) == "line 4, col 3: unknown host operation frobnicate"
  end

  test "host op missing a required argument" do
    source = ~S|on init:
  print(1)
on data("l", r):
  want "l" = log_head()
|

    assert compile_error(source) == "line 4, col 3: log_head is missing log_id"
  end

  test "a want may name a data label declared later in the file" do
    wat =
      compile_ok!(~S|on init:
  want "stored" = storage_set(key: "k", value: 1)
on data("stored", r):
  print(show(r))
|)

    assert wat =~ "storage_set"
  end

  test "host op unexpected argument" do
    source = ~S|on init:
  print(1)
on data("l", r):
  want "l" = log_head(log_id: 1, seq: 2)
|

    assert compile_error(source) == "line 4, col 3: log_head has no argument seq"
  end

  # ============================================================== capacity

  test "constant pool is capped" do
    body = Enum.map_join(1..400, "\n", fn i -> "  print(\"pad pad pad pad pad #{i}\")" end)
    source = "on init:\n" <> body <> "\n"

    assert compile_error(source) == "line 1, col 1: constant pool too large"
  end

  test "effects per turn are capped" do
    source =
      ["on init:"] ++ Enum.map(1..1200, fn _i -> "  print(\"x\")" end)

    source = Enum.join(source, "\n") <> "\n"

    assert compile_error(source) == "line 1, col 1: too many effects for one turn"
  end

  # =============================================================== smoke

  @hello ~S|on init:
  print("hello from dsl")
|

  test "hello compiles to a module watusi can encode" do
    wat = compile_ok!(@hello)

    assert wat =~ ~s|(func (export "handle")|
    assert wat =~ "(func $h_init"
    assert wat =~ "hello from dsl"

    wasm = Watusi.to_wasm(wat)
    assert is_binary(wasm)
    assert byte_size(wasm) > 500
  end

  test "compilation is deterministic" do
    assert compile_ok!(@hello) == compile_ok!(@hello)
  end

  test "full program: every statement kind, encoded by watusi" do
    wat =
      compile_ok!(~S|on init:
  let n = 1
  print("n=" + show(n))
  render(col(text("hello"), row(text("a"), text("b"))))

on tick(t):
  let n = 2
  if n > 1:
    print("big")
  else:
    print("small")
  match n:
    when 2:
      print("two")
    when 3:
      print("three")
    else:
      print("other")

on ui(e):
  draw[fill_rect(x: 0, y: 0, w: 10, h: 10), line(x1: 0, y1: 0, x2: 5, y2: 5, lw: 1)]
  animate(true)

on data("log", r):
  print(show(r))
  want "log" = log_head(log_id: 1)

on err(m):
  print("err: " + m)
|)

    assert is_binary(Watusi.to_wasm(wat))

    # Dispatch extracts every ABI field the handlers subscribe to.
    for field <- ["init", "tick", "ui", "err", "ok"] do
      assert wat =~ field
    end

    # Effects and the want guard land in the init/data handlers.
    assert wat =~ "(func $h_init"
    assert wat =~ "(func $h_data_1"
    assert wat =~ "log_head"
  end

  test "operators lower to the runtime helpers" do
    wat =
      compile_ok!(~S|on init:
  print(show(1 + 2))
  print(show(7 % 2))
  print(show(1 < 2 and 2 <= 2))
  print(show("a" == "a"))
  print(show(-3.5))
|)

    assert wat =~ "(call $v_add"
    assert wat =~ "f64.trunc"
    assert wat =~ "(call $v_lt"
    assert wat =~ "(call $v_text_eq"
    assert wat =~ "(f64.neg"
    assert wat =~ "(f64.const 3.5)"
  end

  test "render lowers to view nodes" do
    wat =
      compile_ok!(~S|on init:
  render(col(text("a"), canvas(64, 32)))
|)

    assert wat =~ ~S|\04\00\00\00\03\00\00\00col|
    assert wat =~ ~S|\04\00\00\00\06\00\00\00canvas|
    assert wat =~ ~S|\04\00\00\00\04\00\00\00kids|
    assert wat =~ ~S|\04\00\00\00\01\00\00\00t|
  end

  test "match lowers to equality tests, arms in source order" do
    wat =
      compile_ok!(~S|on init:
  let e = "down"
  match e:
    when "down":
      print("d")
    when "up":
      print("u")
    else:
      print("x")
|)

    assert wat =~ "(call $v_eq"
    assert wat =~ ~S|\04\00\00\00\04\00\00\00down|
    assert wat =~ ~S|\04\00\00\00\02\00\00\00up|

    # One effect push per arm plus the else.
    h_init = wat |> String.split("(func (export") |> hd()
    assert length(String.split(h_init, "(call $elist_push")) == 4
  end

  test "on data decodes its payload and guards the err branch" do
    wat =
      compile_ok!(~S|on init:
  print("i")
on data("log", r):
  print(show(r))
on err(m):
  print(m)
|)

    assert wat =~ "(call $cbor_val"
    assert wat =~ "(call $v_field (local.get $dm) (i32.const "
  end

  # ============================================================ robustness

  test "diagnostic/1 splits the position out of the same failure" do
    source = ~S|on init:
  print(x)
|

    assert compile_error(source) == "line 2, col 9: x is not defined"

    assert DSL.diagnostic(source) == %{
             line: 2,
             col: 9,
             message: "x is not defined"
           }

    assert DSL.diagnostic(~S|on init:
  print(1)
|) == nil
  end

  test "garbage input returns a diagnostic, never raises" do
    garbage = [
      "(",
      "[",
      "on",
      "on init",
      "on init:",
      "on init:\n  print(",
      "print(1)\n",
      "{{{",
      "\"",
      "on init:\n  draw[",
      "on init:\n  match:",
      "on data:\n  print(1)\n",
      "end\n",
      "  on init:\n    print(1)\n"
    ]

    for source <- garbage do
      result = DSL.compile(source)

      assert match?({:ok, _}, result) or match?({:error, _}, result),
             "compile/1 must return a tuple for #{inspect(source)}, got #{inspect(result)}"
    end
  end
end
