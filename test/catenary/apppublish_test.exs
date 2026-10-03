defmodule Catenary.AppPublishTest do
  use ExUnit.Case, async: false

  alias Catenary.{AppHost, AppPublish, Apps, Preferences}

  @slug "publish-test"
  # A 43-byte base62 key that is not this device's, standing in for the
  # publisher of somebody else's app.
  @foreign_pk String.duplicate("1", 43)

  setup do
    clump_id = Preferences.get(:clump_id)
    identity = Preferences.get(:identity)
    facet_id = Preferences.get(:facet_id)
    author = Catenary.id_for_key(identity)
    log_id = Apps.app_log_id(identity, @slug, facet_id)

    # The channel is this test's alone, so whatever lands in it is taken
    # back out again or the next run starts on somebody else's seqnum.
    on_exit(fn -> Baobab.purge(author, log_id: log_id, clump_id: clump_id) end)

    scope = %{
      app: AppHost.app(clump_id, identity, @slug),
      identity: identity,
      facet_id: facet_id
    }

    %{scope: scope, clump_id: clump_id, identity: identity, facet_id: facet_id, log_id: log_id}
  end

  # What the loop puts on the wire for an entry.
  defp wire(entry), do: entry |> CBOR.encode() |> Base.encode64()

  # The newest thing the channel holds, decoded: reading it back through the
  # store is what proves where a publish landed, not the reply's `ok`.
  defp head(ctx) do
    author = Baobab.Identity.as_base62(ctx.identity)

    seq = Baobab.max_seqnum(author, log_id: ctx.log_id, clump_id: ctx.clump_id)

    %Baobab.Entry{payload: payload} =
      Baobab.log_entry(author, seq, log_id: ctx.log_id, clump_id: ctx.clump_id)

    assert {:ok, value, ""} = CBOR.decode(payload)
    value
  end

  defp foreign_scope(ctx) do
    %{ctx.scope | app: AppHost.app(ctx.clump_id, @foreign_pk, @slug)}
  end

  describe "where an entry lands" do
    test "on the channel the running app's own name derives", ctx do
      reply = AppPublish.publish(ctx.scope, wire(%{type: "note", text: "hello"}))

      assert %{"ok" => true, "seq" => seq} = reply
      assert is_integer(seq) and seq > 0

      assert head(ctx) == %{
               "type" => "note",
               "text" => "hello",
               "v" => 1,
               "app" => ctx.identity <> "/" <> @slug
             }
    end

    test "on the facet this device writes on", ctx do
      assert %{"ok" => true} = AppPublish.publish(ctx.scope, wire(%{type: "note"}))

      other_facet = Baobab.Identity.as_base62(ctx.identity)
      other_log = Apps.app_log_id(ctx.identity, @slug, rem(ctx.facet_id + 1, 256))

      assert Baobab.max_seqnum(other_facet, log_id: other_log, clump_id: ctx.clump_id) == 0
    end

    test "stamped over: the entry cannot claim another app", ctx do
      entry = %{
        "type" => "note",
        "app" => @foreign_pk <> "/elsewhere",
        "v" => 99,
        "log_id" => Apps.manifest_log()
      }

      assert %{"ok" => true} = AppPublish.publish(ctx.scope, wire(entry))

      published = head(ctx)
      assert published["app"] == ctx.identity <> "/" <> @slug
      assert published["v"] == 1
      # Fields the module chose are left alone; only provenance is taken.
      assert published["log_id"] == Apps.manifest_log()
    end
  end

  describe "refusals" do
    test "an identity that is not the publisher's", ctx do
      reply = AppPublish.publish(foreign_scope(ctx), wire(%{type: "note"}))

      assert reply == %{"ok" => false, "error" => "not_the_publisher"}

      # Refused before anything was written, so the channel is untouched.
      author = Baobab.Identity.as_base62(ctx.identity)
      assert Baobab.max_seqnum(author, log_id: ctx.log_id, clump_id: ctx.clump_id) == 0
    end

    test "an entry that is not a map", ctx do
      assert %{"ok" => false, "error" => "entry_not_a_map"} =
               AppPublish.publish(ctx.scope, wire(["not", "a", "map"]))

      assert %{"ok" => false, "error" => "entry_not_a_map"} =
               AppPublish.publish(ctx.scope, wire(42))

      # Not decodable as CBOR at all: refused with whatever the decoder
      # called it, and never written.
      assert %{"ok" => false} = AppPublish.publish(ctx.scope, Base.encode64(<<0xFF, 0xFF>>))
    end

    test "payload that is not one whole CBOR value", ctx do
      trailing = Base.encode64(CBOR.encode(%{type: "note"}) <> CBOR.encode(%{type: "note"}))

      assert %{"ok" => false, "error" => "trailing_bytes"} =
               AppPublish.publish(ctx.scope, trailing)

      assert %{"ok" => false, "error" => "bad_args"} =
               AppPublish.publish(ctx.scope, "not base64 at all!")
    end

    test "an entry with no usable type", ctx do
      assert %{"ok" => false, "error" => "untyped_entry"} =
               AppPublish.publish(ctx.scope, wire(%{text: "no type"}))

      assert %{"ok" => false, "error" => "untyped_entry"} =
               AppPublish.publish(ctx.scope, wire(%{type: 7}))
    end

    test "an entry over the size cap, before it is decoded", ctx do
      # Long enough that the wire string itself is past the cap, so base64
      # is never run over it.
      assert %{"ok" => false, "error" => "entry_too_large"} =
               AppPublish.publish(ctx.scope, String.duplicate("a", 1024 * 1024))

      oversized = wire(%{type: "note", text: String.duplicate("a", 70 * 1024)})

      assert %{"ok" => false, "error" => "entry_too_large"} =
               AppPublish.publish(ctx.scope, oversized)
    end

    test "a scope the LiveView did not assemble", ctx do
      assert %{"ok" => false, "error" => "bad_args"} =
               AppPublish.publish(%{app: ctx.scope.app}, wire(%{type: "note"}))

      assert %{"ok" => false, "error" => "bad_args"} =
               AppPublish.publish(%{ctx.scope | facet_id: 999}, wire(%{type: "note"}))

      assert %{"ok" => false, "error" => "bad_args"} =
               AppPublish.publish(ctx.scope, :not_a_string)
    end
  end
end
