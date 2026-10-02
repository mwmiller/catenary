defmodule Catenary.AppHostTest do
  use ExUnit.Case, async: false

  alias Catenary.{AppHost, AppKV, Preferences}

  @base_mask 0x00FFFFFFFFFFFFFF
  @family_mask 0x00FF000000000000

  # A base62 author that exists in no identity store. Blocking them costs
  # nothing — there is nothing of theirs to purge — and it is exactly the
  # shape an author reaches the host in.
  @foreign_author String.duplicate("1", 43)

  setup do
    clump_id = Preferences.get(:clump_id)
    identity = Preferences.get(:identity)

    app = AppHost.app(clump_id, identity, "example-app")
    other_app = AppHost.app(clump_id, identity, "other-app")
    other_publisher = AppHost.app(clump_id, "someone-else", "example-app")

    # Stored keys outlive a single test, so start each one from the empty
    # store an app would see the first time it ran.
    Enum.each([app, other_app, other_publisher], &AppKV.clear/1)

    %{
      clump_id: clump_id,
      app: app,
      other_app: other_app,
      other_publisher: other_publisher
    }
  end

  # Appending to the active identity's own log would outlive the test, so
  # this fixture is torn down the same way it was set up.
  defp with_entry(ctx) do
    author = Catenary.id_for_key(Preferences.get(:identity))
    log_id = Catenary.Apps.manifest_log()

    Baobab.append_log("apphost entry", author, log_id: log_id, clump_id: ctx.clump_id)

    on_exit(fn ->
      Baobab.purge(author, log_id: log_id, clump_id: ctx.clump_id)
    end)

    Map.merge(ctx, %{author: author, log_id: log_id})
  end

  # A pattern block, registered and withdrawn around the test. Unlike
  # `Catenary.BlockLog.block_name/2` this purges nothing, which is what lets
  # the entry stay put long enough to prove it became unreadable.
  defp block_pattern(ctx, pattern) do
    Baobab.ClumpMeta.block_pattern(pattern, ctx.clump_id)

    on_exit(fn ->
      Baobab.ClumpMeta.unblock_pattern(pattern, ctx.clump_id)
    end)

    ctx
  end

  defp read(ctx, attrs \\ %{}) do
    args =
      Map.merge(
        %{author: ctx.author, log_id: ctx.log_id, seq: "max"},
        attrs
      )

    AppHost.handle(ctx.app, "log_read", args)
  end

  # A payload comes back tagged as bytes so that it reaches the worker as
  # bytes rather than through a text conversion; unwrapped here to keep the
  # assertions about what was stored readable.
  defp payload({:ok, %CBOR.Tag{tag: :bytes, value: value}}), do: {:ok, value}
  defp payload(other), do: other

  describe "the app context" do
    test "carries the three parts every key is scoped by" do
      assert AppHost.app("clump-a", "publisher", "slug") ==
               %{clump_id: "clump-a", pk: "publisher", slug: "slug"}
    end

    test "a context missing any part is refused before an operation runs" do
      assert {:error, :bad_app} =
               AppHost.handle(%{clump_id: "c", pk: "p"}, "storage_get", %{key: "k"})

      assert {:error, :bad_app} =
               AppHost.handle(%{clump_id: 1, pk: "p", slug: "s"}, "storage_get", %{key: "k"})
    end
  end

  describe "the operation allow-list" do
    test "an unlisted operation is refused without a lookup", ctx do
      assert {:error, :unsupported_op} = AppHost.handle(ctx.app, "read_everything", %{})
      refute "read_everything" in AppHost.ops()
    end

    test "every advertised operation is dispatched", ctx do
      for op <- AppHost.ops() do
        refute AppHost.handle(ctx.app, op, %{}) == {:error, :unsupported_op},
               "#{op} is advertised but not dispatched"
      end
    end

    test "a malformed message is an error rather than a crash", ctx do
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "log_read", "not a map")
      assert {:error, :bad_args} = AppHost.handle(ctx.app, 1_234, %{})
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "log_read", nil)
    end
  end

  describe "log_read" do
    test "returns the payload of a stored entry", ctx do
      ctx = with_entry(ctx)
      assert {:ok, "apphost entry"} = payload(read(ctx))
    end

    test "accepts arguments keyed by string, as they arrive from the worker", ctx do
      ctx = with_entry(ctx)

      assert {:ok, "apphost entry"} =
               AppHost.handle(ctx.app, "log_read", %{
                 "author" => ctx.author,
                 "log_id" => ctx.log_id,
                 "seq" => "max"
               })
               |> payload()
    end

    test "reads the same author named either way", ctx do
      ctx = with_entry(ctx)

      base62 = Baobab.Identity.as_base62(ctx.author)
      assert base62 != ctx.author
      assert {:ok, "apphost entry"} = ctx |> read(%{author: base62}) |> payload()
    end

    test "names an entry that is not there as missing, not as blocked", ctx do
      ctx = with_entry(ctx)

      assert {:error, :missing} = read(ctx, %{seq: 99_999})
      assert {:error, :missing} = read(ctx, %{author: @foreign_author, seq: 1})
    end

    test "incomplete or malformed arguments are refused", ctx do
      ctx = with_entry(ctx)

      assert {:error, :bad_args} = AppHost.handle(ctx.app, "log_read", %{})
      assert {:error, :bad_args} = read(ctx, %{log_id: nil})
      assert {:error, :bad_args} = read(ctx, %{seq: 0})
      assert {:error, :bad_args} = read(ctx, %{seq: -1})
      assert {:error, :bad_args} = read(ctx, %{log_id: -1})
      assert {:error, :bad_args} = read(ctx, %{author: "not-an-identity"})
    end

    test "a blocked author is refused before the store is touched", ctx do
      Baobab.ClumpMeta.block(@foreign_author, ctx.clump_id)
      on_exit(fn -> Baobab.ClumpMeta.unblock(@foreign_author, ctx.clump_id) end)

      assert {:error, :blocked} =
               AppHost.handle(ctx.app, "log_read", %{
                 author: @foreign_author,
                 log_id: 0,
                 seq: 1
               })
    end

    test "a log type blocked by name is unreadable even though the entry is there", ctx do
      ctx = with_entry(ctx)
      assert {:ok, _} = read(ctx)

      base = Bitwise.band(ctx.log_id, @base_mask)
      block_pattern(ctx, %{op: :eq, mask: @base_mask, v: base})

      assert read(ctx) == {:error, :blocked}
    end

    test "a blocked family is unreadable even though the entry is there", ctx do
      ctx = with_entry(ctx)
      assert {:ok, _} = read(ctx)

      family = Bitwise.bsr(ctx.log_id, 48)
      block_pattern(ctx, %{op: :eq, mask: @family_mask, v: Bitwise.bsl(family, 48)})

      assert read(ctx) == {:error, :blocked}
    end
  end

  describe "app-scoped storage" do
    test "a value round-trips and an unset key answers plainly", ctx do
      assert {:error, :not_found} = AppHost.handle(ctx.app, "storage_get", %{key: "counter"})

      assert {:ok, :stored} =
               AppHost.handle(ctx.app, "storage_set", %{key: "counter", value: 3})

      assert {:ok, 3} = AppHost.handle(ctx.app, "storage_get", %{key: "counter"})
    end

    test "string keys are accepted as they arrive from the worker", ctx do
      assert {:ok, :stored} =
               AppHost.handle(ctx.app, "storage_set", %{"key" => "title", "value" => "hi"})

      assert {:ok, "hi"} = AppHost.handle(ctx.app, "storage_get", %{"key" => "title"})
    end

    test "a different listing cannot see another listing's keys", ctx do
      assert {:ok, :stored} =
               AppHost.handle(ctx.app, "storage_set", %{key: "counter", value: 3})

      assert {:error, :not_found} =
               AppHost.handle(ctx.other_app, "storage_get", %{key: "counter"})
    end

    test "a different publisher cannot see another publisher's keys", ctx do
      assert {:ok, :stored} =
               AppHost.handle(ctx.app, "storage_set", %{key: "counter", value: 3})

      assert {:error, :not_found} =
               AppHost.handle(ctx.other_publisher, "storage_get", %{key: "counter"})
    end

    test "malformed storage arguments are refused", ctx do
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "storage_get", %{})
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "storage_get", %{key: 7})
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "storage_set", %{key: "k"})
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "storage_set", %{value: 1})
    end

    test "clearing local data leaves another listing's keys alone", ctx do
      assert {:ok, :stored} =
               AppHost.handle(ctx.app, "storage_set", %{key: "counter", value: 3})

      assert {:ok, :stored} =
               AppHost.handle(ctx.other_app, "storage_set", %{key: "counter", value: 9})

      on_exit(fn -> AppKV.clear(ctx.other_app) end)

      assert :ok = AppKV.clear(ctx.app)

      assert {:error, :not_found} = AppHost.handle(ctx.app, "storage_get", %{key: "counter"})
      assert {:ok, 9} = AppHost.handle(ctx.other_app, "storage_get", %{key: "counter"})
    end
  end
end
