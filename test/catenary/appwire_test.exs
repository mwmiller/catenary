defmodule Catenary.AppWireTest do
  use ExUnit.Case, async: false

  alias Catenary.{AppHost, AppKV, AppWire, Preferences}

  @foreign_author String.duplicate("1", 43)

  setup do
    clump_id = Preferences.get(:clump_id)
    identity = Preferences.get(:identity)

    app = AppHost.app(clump_id, identity, "viewer-app")
    Enum.each([app], &AppKV.clear/1)

    %{app: app, clump_id: clump_id}
  end

  defp with_entry(ctx) do
    author = Catenary.id_for_key(Preferences.get(:identity))
    log_id = Catenary.Apps.manifest_log()

    Baobab.append_log("wire entry", author, log_id: log_id, clump_id: ctx.clump_id)

    on_exit(fn ->
      Baobab.purge(author, log_id: log_id, clump_id: ctx.clump_id)
    end)

    Map.merge(ctx, %{author: author, log_id: log_id})
  end

  describe "carrying arguments" do
    test "a storage value survives the trip out and back", ctx do
      reply = AppWire.request(ctx.app, "storage_set", AppWire.encode_args(%{key: "k", value: 41}))
      assert %{"ok" => true} = reply
      assert {:ok, "stored"} = AppWire.decode_data(reply)

      reply = AppWire.request(ctx.app, "storage_get", AppWire.encode_args(%{key: "k"}))
      assert {:ok, 41} = AppWire.decode_data(reply)
    end

    test "string keys from a worker are read the same as atom keys", ctx do
      reply =
        AppWire.request(
          ctx.app,
          "storage_set",
          AppWire.encode_args(%{"key" => "k", "value" => 1})
        )

      assert {:ok, "stored"} = AppWire.decode_data(reply)
    end

    test "payload bytes come back intact", ctx do
      ctx = with_entry(ctx)

      reply =
        AppWire.request(
          ctx.app,
          "log_read",
          AppWire.encode_args(%{author: ctx.author, log_id: ctx.log_id, seq: "max"})
        )

      # Payloads travel as CBOR byte strings: a plain binary would be encoded
      # as text and put through a UTF-8 conversion on the way to the worker.
      assert {:ok, %CBOR.Tag{tag: :bytes, value: "wire entry"}} =
               AppWire.decode_data(reply)
    end

    test "a refusal is a plain error string the worker can report", ctx do
      reply = AppWire.request(ctx.app, "storage_get", AppWire.encode_args(%{key: "unset"}))
      assert reply == %{"ok" => false, "error" => "not_found"}

      reply = AppWire.request(ctx.app, "storage_get", AppWire.encode_args(%{key: 7}))
      assert reply == %{"ok" => false, "error" => "bad_args"}
    end

    test "a blocked read says so rather than as a decode failure", ctx do
      Baobab.ClumpMeta.block(@foreign_author, ctx.clump_id)
      on_exit(fn -> Baobab.ClumpMeta.unblock(@foreign_author, ctx.clump_id) end)

      reply =
        AppWire.request(
          ctx.app,
          "log_read",
          AppWire.encode_args(%{author: @foreign_author, log_id: 0, seq: 1})
        )

      assert reply == %{"ok" => false, "error" => "blocked"}
    end
  end

  describe "malformed requests" do
    test "anything that is not one well-formed CBOR value is refused", ctx do
      valid = CBOR.encode(%{"key" => "k"})

      assert %{"ok" => false, "error" => "trailing_bytes"} =
               AppWire.request(ctx.app, "storage_get", Base.encode64(valid <> "junk"))

      assert %{"ok" => false, "error" => error} =
               AppWire.request(ctx.app, "storage_get", Base.encode64(binary_part(valid, 0, 2)))

      assert is_binary(error)

      assert %{"ok" => false, "error" => error} =
               AppWire.request(ctx.app, "storage_get", "not base64 at all")

      assert is_binary(error)
    end

    test "decoded arguments that are not a map never reach the host", ctx do
      assert %{"ok" => false, "error" => "bad_args"} =
               AppWire.request(ctx.app, "storage_get", Base.encode64(CBOR.encode([1, 2, 3])))
    end

    test "a missing or non-binary op and args are refused outright", ctx do
      assert %{"ok" => false, "error" => "bad_args"} = AppWire.request(ctx.app, nil, nil)

      assert %{"ok" => false, "error" => "bad_args"} =
               AppWire.request(ctx.app, "storage_get", %{})

      assert %{"ok" => false, "error" => "bad_args"} = AppWire.request(ctx.app, 1_234, "AAAA")
    end

    test "an operation outside the allow-list is named", ctx do
      assert %{"ok" => false, "error" => "unsupported_op"} =
               AppWire.request(ctx.app, "read_everything", AppWire.encode_args(%{}))

      refute "read_everything" in AppHost.ops()
    end
  end
end
