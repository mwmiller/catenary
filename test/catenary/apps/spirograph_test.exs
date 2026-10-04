defmodule Catenary.Apps.SpirographTest do
  use ExUnit.Case, async: true

  alias Catenary.Apps.{DSL, Spirograph}

  # The example is the product: pasted into the playground and released
  # from the panel, it has to keep compiling as the language moves. This
  # is the same round trip the browser takes, minus the browser.

  test "the spirograph source compiles to a module watusi can encode" do
    assert {:ok, wat} = DSL.compile(Spirograph.source())

    assert wat =~ "(func $h_init"
    assert wat =~ "(func $h_ui"
    assert wat =~ "(func $h_err"

    # Two labels, two data handlers: the feed and storage's shared
    # save/load channel.
    assert length(Regex.scan(~r/\(func \$h_data_\d+/, wat)) == 2

    # The shape the drawing depends on: a counted loop over the curve,
    # trig calls into the hand-written runtime (WebAssembly has no
    # sin instruction), list push, payload decode.
    assert wat =~ ~r/\(block \$rep\d+\b/
    assert wat =~ "(call $sin_f"
    assert wat =~ "(call $cos_f"
    assert wat =~ "(call $v_push"
    assert wat =~ "(call $v_decode"

    # Everything the gestures reach for, by the names it crosses the
    # effect wire under.
    assert wat =~ "storage_get"
    assert wat =~ "storage_set"
    assert wat =~ "channel"
    assert wat =~ "publish"

    assert is_binary(Watusi.to_wasm(wat))
  end

  test "the example compiles the same way twice" do
    assert DSL.compile(Spirograph.source()) == DSL.compile(Spirograph.source())
  end

  test "the source is a binary with handlers and no tabs" do
    source = Spirograph.source()

    assert is_binary(source)
    assert source =~ "on init:"
    assert source =~ "on ui("
    refute source =~ "\t"
  end
end
