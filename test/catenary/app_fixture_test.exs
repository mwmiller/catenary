defmodule Catenary.AppFixtureTest do
  use ExUnit.Case, async: true

  alias Catenary.AppFixture
  alias Catenary.AppFixture.Refuser

  @magic <<0, 97, 115, 109, 1, 0, 0, 0>>

  test "compiles to a module with the exports the harness looks for" do
    wasm = AppFixture.wasm()

    assert binary_part(wasm, 0, byte_size(@magic)) == @magic
    # Export names are length-prefixed, so the search doubles as a check
    # that the module really exported them rather than merely mentioned them
    # in some other section.
    assert :binary.match(wasm, <<6, "memory">>) != :nomatch, "memory is not exported"
    assert :binary.match(wasm, <<6, "handle">>) != :nomatch, "handle is not exported"
  end

  test "carries the effects each state of the loop emits" do
    wasm = AppFixture.wasm()

    assert_effects(wasm, AppFixture.first_effects())
    assert_effects(wasm, AppFixture.reply_effects())
  end

  test "the second state is distinguishable from the first" do
    # If both states emitted the same effects there would be nothing to see
    # once a reply arrived, and a harness that never delivered one would
    # look like it worked.
    first = AppFixture.first_effects()
    reply = AppFixture.reply_effects()

    refute first == reply
    refute Enum.any?(first, &(&1["do"] == "render"))
    assert Enum.any?(reply, &(&1["do"] == "render"))
  end

  test "the refusing fixture asks for an operation no host answers" do
    wasm = Refuser.wasm()

    assert binary_part(wasm, 0, byte_size(@magic)) == @magic
    assert :binary.match(wasm, <<6, "memory">>) != :nomatch, "memory is not exported"
    assert :binary.match(wasm, <<6, "handle">>) != :nomatch, "handle is not exported"

    assert_effects(wasm, Refuser.first_effects())
    assert_effects(wasm, Refuser.reply_effects())
  end

  test "the refusing fixture only advances once a reply has been delivered" do
    # Its first state is a `want` the host refuses, so the second state's
    # render is only reachable if the refusal came back as the ABI's `err`
    # and the app was still running to deliver it.
    first = Refuser.first_effects()
    reply = Refuser.reply_effects()

    assert Enum.any?(first, &(&1["do"] == "want" and &1["op"] == "watch"))
    refute Enum.any?(first, &(&1["do"] == "render"))
    assert Enum.any?(reply, &(&1["do"] == "render"))
    refute first == reply
  end

  defp assert_effects(wasm, effects) do
    encoded = CBOR.encode(effects)

    assert :binary.match(wasm, encoded) != :nomatch,
           "the compiled module does not contain #{inspect(effects)}"

    # What a decoder sees has to be the term the fixture was written as —
    # that is the same agreement the wire protocol relies on.
    assert {:ok, ^effects, ""} = CBOR.decode(encoded)
  end
end
