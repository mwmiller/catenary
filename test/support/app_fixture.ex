defmodule Catenary.AppFixture do
  @moduledoc """
  A hand-written WAT module that stands in for a published app while the
  harness is built.

  It is the smallest module that exercises every step of the ABI the
  harness implements:

    * `memory` is exported, and the harness writes the message into it;
    * `handle(in_ptr, in_len)` returns a pointer and leaves the length of
      its result at address 0, which is how the harness knows how much to
      read back;
    * the first call emits a `print` and a `want`, so the harness has to
      reach the host and come back before anything else can happen;
    * only a delivered reply advances the state, so the second call's
      `render` and `print` can only appear if the whole loop worked —
      a failed `want` never produces a reply to deliver.

  The module is compiled with `watusi` rather than shipped as a binary, so
  the effects it emits stay ordinary Elixir terms a test can assert on,
  encoded with the same `cbor` package the host answers with. That is also
  what makes the fixture a real ABI check: the bytes in the module and the
  bytes on the wire come from one encoder.

  This lives under `test/support` because it is scaffolding — it is loaded
  by tests directly and by `scripts/make-app-fixture.exs` for a manual run
  in the browser, and it has no place in a release.
  """

  # Where the two result blobs are placed. Anything below @input_base is the
  # module's own to use; the harness writes messages at @input_base and up.
  @first_result 16
  @reply_result 512
  @length_slot 0

  @doc """
  What the module emits on the first call: a print, then a host round trip.

  The `want` is what gates everything after it — the harness only delivers
  a `data` message once the host has answered.
  """
  @spec first_effects() :: [map()]
  def first_effects do
    [
      %{"do" => "print", "text" => "init"},
      %{
        "do" => "want",
        "ref" => 1,
        "op" => "storage_set",
        "args" => %{"key" => "hello", "value" => 41}
      }
    ]
  end

  @doc """
  What the module emits once the reply has been delivered.

  The view is a node rather than a plain map, so it exercises every
  widget the v1 vocabulary has. The refusing fixture keeps a plain map
  on purpose: a value that is not a node takes the text dump path,
  which is how a module written before the renderer still renders.
  """
  @spec reply_effects() :: [map()]
  def reply_effects do
    [
      %{"do" => "render", "view" => view()},
      %{"do" => "print", "text" => "ready"}
    ]
  end

  @doc """
  The fixture's view-model: a column of text, a row of labels and a
  canvas placeholder (tier 1 drawing is step 4d).
  """
  @spec view() :: map()
  def view do
    %{
      "t" => "col",
      "kids" => [
        %{"t" => "text", "s" => "ready"},
        %{
          "t" => "row",
          "kids" => [
            %{"t" => "text", "s" => "hello-app"},
            %{"t" => "text", "s" => "v1"}
          ]
        },
        %{"t" => "canvas", "w" => 96, "h" => 48}
      ]
    }
  end

  @doc """
  Compile the fixture. Returns the raw WASM binary.
  """
  @spec wasm() :: binary
  def wasm, do: wat(first_effects(), reply_effects()) |> Watusi.to_wasm()

  @doc """
  The WAT the fixture compiles from — what a publish would record as the
  module's source.
  """
  @spec wat() :: binary
  def wat, do: wat(first_effects(), reply_effects())

  @doc """
  Compile a two-state module: `first` on the first call, `reply` on every
  one after it. The state machine is the same one the fixtures need, so it
  lives here rather than being written out twice.
  """
  @spec build([map()], [map()]) :: binary
  def build(first, reply), do: wat(first, reply) |> Watusi.to_wasm()

  @doc """
  The WAT text `build/2` compiles: the same two-state module, as source.
  """
  @spec wat([map()], [map()]) :: binary
  def wat(first, reply) do
    first = CBOR.encode(first)
    reply = CBOR.encode(reply)

    """
    (module
      (memory (export "memory") 1)
      (global $state (mut i32) (i32.const 0))
      (data (i32.const #{@first_result}) "#{escape(first)}")
      (data (i32.const #{@reply_result}) "#{escape(reply)}")
      (func (export "handle") (param $in i32) (param $in_len i32) (result i32)
        (if (result i32) (i32.eqz (global.get $state))
          (then
            (global.set $state (i32.const 1))
            (i32.store (i32.const #{@length_slot}) (i32.const #{byte_size(first)}))
            (i32.const #{@first_result}))
          (else
            (i32.store (i32.const #{@length_slot}) (i32.const #{byte_size(reply)}))
            (i32.const #{@reply_result})))))
    """
  end

  # WAT strings take byte escapes as two hex digits, which keeps arbitrary
  # CBOR bytes out of the source text.
  defp escape(bytes) do
    for <<byte <- bytes>>, into: "" do
      "\\" <> Base.encode16(<<byte>>, case: :lower)
    end
  end
end

defmodule Catenary.AppFixture.Refuser do
  @moduledoc """
  The refusal path, as a module: the fixture for the ABI's `err` message.

  Its first state asks for `watch`, an operation no host answers yet, so
  the reply is `{"msg":"err"}` rather than `{"msg":"data"}`. Nothing moves
  the module on but a delivered reply, so the second state's render and
  print only appear if the refusal reached it — and only then is the app
  still running to show them. Where the module was started decides whether
  it gets that far: a host refusal is a strike (§3), and a `.wasm` dropped
  into the playground is judged on its first tick, so there the strike
  refuses the gate and the run stops with the reply delivered but no turn
  left to answer it. The app viewer's pane carries the strike like any
  other and ticks on into the second state.
  """

  alias Catenary.AppFixture

  @doc """
  What the module emits on the first call: a print, then a `want` the host
  cannot answer.
  """
  @spec first_effects() :: [map()]
  def first_effects do
    [
      %{"do" => "print", "text" => "asking"},
      %{"do" => "want", "ref" => 1, "op" => "watch", "args" => %{}}
    ]
  end

  @doc """
  What the module emits once the refusal has been delivered.
  """
  @spec reply_effects() :: [map()]
  def reply_effects do
    [
      %{"do" => "render", "view" => %{"text" => "refused, still running"}},
      %{"do" => "print", "text" => "carried on"}
    ]
  end

  @doc """
  Compile the refusing fixture. Returns the raw WASM binary.
  """
  @spec wasm() :: binary
  def wasm, do: AppFixture.build(first_effects(), reply_effects())

  @doc """
  The WAT the refusing fixture compiles from.
  """
  @spec wat() :: binary
  def wat, do: AppFixture.wat(first_effects(), reply_effects())
end
