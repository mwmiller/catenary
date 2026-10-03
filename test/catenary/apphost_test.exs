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

  # The manifest log is shared with the publish tests, which leave their
  # entries standing — they have no teardown that could take them back — so
  # these fixtures begin by emptying it again. Without that, "from 1" and a
  # reference to entry 1 only mean the test's own first entry when the test
  # happens to run first.
  defp start_clean(ctx, author, log_id) do
    Baobab.purge(author, log_id: log_id, clump_id: ctx.clump_id)
  end

  # Appending to the active identity's own log would outlive the test, so
  # this fixture is torn down the same way it was set up.
  defp with_entry(ctx) do
    author = Catenary.id_for_key(Preferences.get(:identity))
    log_id = Catenary.Apps.manifest_log()
    start_clean(ctx, author, log_id)

    Baobab.append_log("apphost entry", author, log_id: log_id, clump_id: ctx.clump_id)

    on_exit(fn ->
      Baobab.purge(author, log_id: log_id, clump_id: ctx.clump_id)
    end)

    Map.merge(ctx, %{author: author, log_id: log_id})
  end

  # The same fixture with payloads worth reading back, and the sequence
  # numbers they landed on, which is what a range is answered against.
  defp with_entries(ctx, payloads) do
    author = Catenary.id_for_key(Preferences.get(:identity))
    log_id = Catenary.Apps.manifest_log()
    start_clean(ctx, author, log_id)

    seqs =
      for payload <- payloads do
        Baobab.append_log(payload, author, log_id: log_id, clump_id: ctx.clump_id)
        Baobab.max_seqnum(author, log_id: log_id, clump_id: ctx.clump_id)
      end

    on_exit(fn ->
      Baobab.purge(author, log_id: log_id, clump_id: ctx.clump_id)
    end)

    Map.merge(ctx, %{author: author, log_id: log_id, seqs: seqs, payloads: payloads})
  end

  # An entry whose payload is a map rather than prose, which is what a
  # listing or a journal entry carries — and where an entry's own
  # references live.
  defp with_payload(ctx, term) do
    author = Catenary.id_for_key(Preferences.get(:identity))
    log_id = Catenary.Apps.manifest_log()
    start_clean(ctx, author, log_id)

    Baobab.append_log(CBOR.encode(term), author, log_id: log_id, clump_id: ctx.clump_id)
    seq = Baobab.max_seqnum(author, log_id: log_id, clump_id: ctx.clump_id)

    on_exit(fn ->
      Baobab.purge(author, log_id: log_id, clump_id: ctx.clump_id)
    end)

    Map.merge(ctx, %{author: author, log_id: log_id, seq: seq})
  end

  # An index row written straight into the table the workers own: the host
  # reads those tables, so a test puts one there rather than waiting for a
  # log to be indexed. Workers key entries in base62, so the caller passes
  # the key in that form. Whatever was under the key goes back afterwards,
  # because a row the developer's own store already holds is not the test's
  # to delete.
  defp with_index(table, key, rows) do
    case :ets.whereis(table) do
      :undefined -> Catenary.Indices.empty_table(table)
      _table -> :ok
    end

    previous = :ets.lookup(table, key)
    true = :ets.insert(table, {key, rows})

    on_exit(fn -> restore(table, key, previous) end)
  end

  defp restore(table, key, previous) do
    with true <- :ets.whereis(table) != :undefined,
         [] <- previous do
      :ets.delete(table, key)
    else
      [entry] -> :ets.insert(table, entry)
      _ -> :ok
    end
  end

  # The form blocks and index tables are keyed by. `id_for_key/1` answers
  # with the alias, which is the same identity spelled differently.
  defp b62(author), do: Baobab.Identity.as_base62(author)

  defp range(ctx, attrs) do
    AppHost.handle(ctx.app, "log_range", Map.merge(%{log_id: ctx.log_id}, attrs))
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

    test "an author the module never names is its own", ctx do
      ctx = with_entries(ctx, ["mine"])
      [seq] = ctx.seqs

      assert {:ok, "mine"} =
               AppHost.handle(ctx.app, "log_read", %{log_id: ctx.log_id, seq: seq}) |> payload()
    end
  end

  describe "log_head" do
    test "answers with the newest sequence number on a log", ctx do
      ctx = with_entries(ctx, ["one", "two"])
      [_, seq] = ctx.seqs

      assert {:ok, %{"seq" => ^seq}} =
               AppHost.handle(ctx.app, "log_head", %{log_id: ctx.log_id})
    end

    test "reads an author it was not given as the app's own", ctx do
      ctx = with_entries(ctx, ["one"])

      assert {:ok, head} =
               AppHost.handle(ctx.app, "log_head", %{author: ctx.author, log_id: ctx.log_id})

      assert {:ok, ^head} = AppHost.handle(ctx.app, "log_head", %{log_id: ctx.log_id})
    end

    test "a log nothing has been written to is missing rather than empty", ctx do
      assert {:error, :missing} = AppHost.handle(ctx.app, "log_head", %{log_id: 999_999})
    end

    test "a blocked log is refused before anything is read", ctx do
      ctx = with_entries(ctx, ["one"])
      base = Bitwise.band(ctx.log_id, @base_mask)
      block_pattern(ctx, %{op: :eq, mask: @base_mask, v: base})

      assert {:error, :blocked} = AppHost.handle(ctx.app, "log_head", %{log_id: ctx.log_id})
    end

    test "incomplete or malformed arguments are refused", ctx do
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "log_head", %{})
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "log_head", %{log_id: -1})
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "log_head", %{log_id: 0, author: 7})

      assert {:error, :bad_args} =
               AppHost.handle(ctx.app, "log_head", %{log_id: 0, author: "not-an-identity"})
    end
  end

  describe "log_range" do
    test "returns a page of entries in order, payload and all", ctx do
      ctx = with_entries(ctx, ["one", "two", "three"])
      [first | _] = ctx.seqs

      assert {:ok, entries} = range(ctx, %{"from" => first, "count" => 10})

      assert Enum.map(entries, & &1["seq"]) == ctx.seqs

      assert Enum.map(entries, & &1["payload"]) ==
               Enum.map(ctx.payloads, &%CBOR.Tag{tag: :bytes, value: &1})
    end

    test "count takes the page from the front of the range", ctx do
      ctx = with_entries(ctx, ["one", "two", "three"])
      [first | _] = ctx.seqs
      assert {:ok, [_one, two]} = range(ctx, %{from: first, count: 2})
      assert two["seq"] == Enum.at(ctx.seqs, 1)
    end

    test "a range starting past the newest entry answers with nothing", ctx do
      ctx = with_entries(ctx, ["one"])
      assert {:ok, []} = range(ctx, %{from: 99_999, count: 10})
      assert {:ok, []} = range(ctx, %{count: 0})
    end

    test "asking for more than a page holds is not an error", ctx do
      ctx = with_entries(ctx, ["one", "two"])

      assert {:ok, entries} = range(ctx, %{from: 1, count: 1000})
      assert length(entries) <= 64
    end

    test "from skips everything older than it", ctx do
      ctx = with_entries(ctx, ["one", "two", "three"])
      [_, second | _] = ctx.seqs

      assert {:ok, entries} = range(ctx, %{from: second, count: 10})
      assert Enum.map(entries, & &1["seq"]) == Enum.drop(ctx.seqs, 1)
    end

    test "blocked entries are dropped from the page", ctx do
      ctx = with_entries(ctx, ["one", "two"])
      base = Bitwise.band(ctx.log_id, @base_mask)
      block_pattern(ctx, %{op: :eq, mask: @base_mask, v: base})

      assert {:ok, []} = range(ctx, %{from: 1, count: 10})
    end

    test "the page stops once it has as much payload as it will carry", ctx do
      big = String.duplicate("x", 150 * 1024)
      ctx = with_entries(ctx, [big, big])

      assert {:ok, entries} = range(ctx, %{from: 1, count: 10})
      assert length(entries) == 1
      assert [%CBOR.Tag{value: payload}] = Enum.map(entries, & &1["payload"])
      assert byte_size(payload) == 150 * 1024
    end

    test "arguments as they arrive from the worker", ctx do
      ctx = with_entries(ctx, ["one"])
      [first] = ctx.seqs

      assert {:ok, [%{"seq" => ^first, "payload" => %CBOR.Tag{value: "one"}}]} =
               AppHost.handle(ctx.app, "log_range", %{
                 "log_id" => ctx.log_id,
                 "from" => first,
                 "count" => 4
               })
    end

    test "incomplete or malformed arguments are refused", ctx do
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "log_range", %{})
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "log_range", %{log_id: -1})
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "log_range", %{log_id: 0, from: 0})
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "log_range", %{log_id: 0, count: -1})

      assert {:error, :bad_args} =
               AppHost.handle(ctx.app, "log_range", %{log_id: 0, author: "not-an-identity"})
    end
  end

  describe "refs" do
    test "what an entry names comes out of its payload", ctx do
      ctx = with_payload(ctx, %{"references" => []})

      ctx =
        with_payload(ctx, %{
          "references" => [[ctx.author, ctx.log_id, 1], ["nope"], [ctx.author, ctx.log_id]]
        })

      assert {:ok, %{"back-refs" => back, "refs" => [], "fore-refs" => []}} =
               AppHost.handle(ctx.app, "refs", %{log_id: ctx.log_id, seq: ctx.seq})

      assert back == [[b62(ctx.author), ctx.log_id, 1]]
    end

    test "what names an entry comes from the index, split on reply logs", ctx do
      ctx = with_payload(ctx, %{"references" => []})
      entry = {b62(ctx.author), ctx.log_id, ctx.seq}
      reply_log = List.first(QuaggaDef.logs_for_name(:reply))

      with_index(:references, entry, [
        {10, {b62(ctx.author), ctx.log_id, 2}},
        {11, {"somewhere-else", reply_log, 1}}
      ])

      assert {:ok, %{"back-refs" => [], "refs" => plain, "fore-refs" => fore}} =
               AppHost.handle(ctx.app, "refs", %{log_id: ctx.log_id, seq: ctx.seq})

      assert plain == [{b62(ctx.author), ctx.log_id, 2}]
      assert fore == [{"somewhere-else", reply_log, 1}]
    end

    test "arguments keyed by string, as they arrive from the worker", ctx do
      ctx = with_payload(ctx, %{"references" => []})

      assert {:ok, %{"back-refs" => []}} =
               AppHost.handle(ctx.app, "refs", %{
                 "log_id" => ctx.log_id,
                 "seq" => ctx.seq
               })
    end

    test "`seq` may name the newest entry rather than a number", ctx do
      ctx = with_payload(ctx, %{"references" => []})
      ctx = with_payload(ctx, %{"references" => [[ctx.author, ctx.log_id, 1]]})

      assert {:ok, %{"back-refs" => [[_, _, 1]]}} =
               AppHost.handle(ctx.app, "refs", %{log_id: ctx.log_id, seq: "max"})
    end

    test "a blocked entry is refused rather than answered", ctx do
      ctx = with_payload(ctx, %{"references" => []})
      base = Bitwise.band(ctx.log_id, @base_mask)
      block_pattern(ctx, %{op: :eq, mask: @base_mask, v: base})

      assert {:error, :blocked} =
               AppHost.handle(ctx.app, "refs", %{log_id: ctx.log_id, seq: ctx.seq})
    end

    test "an entry the store does not hold is missing", ctx do
      ctx = with_payload(ctx, %{"references" => []})

      assert {:error, :missing} =
               AppHost.handle(ctx.app, "refs", %{log_id: ctx.log_id, seq: 99})
    end

    test "incomplete or malformed arguments are refused", ctx do
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "refs", %{})
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "refs", %{log_id: -1, seq: 1})
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "refs", %{log_id: 1, seq: 0})

      assert {:error, :bad_args} =
               AppHost.handle(ctx.app, "refs", %{log_id: 1, seq: 1, author: "not-an-identity"})
    end
  end

  describe "entry_meta" do
    test "tags, reactions and mentions come from their indexes", ctx do
      ctx = with_payload(ctx, %{})
      entry = {b62(ctx.author), ctx.log_id, ctx.seq}

      with_index(:tags, entry, [{100, "elixir"}])
      with_index(:reactions, entry, [{101, "LIKE"}])
      with_index(:mentions, entry, [{102, "someone-else"}])

      assert {:ok, meta} =
               AppHost.handle(ctx.app, "entry_meta", %{log_id: ctx.log_id, seq: ctx.seq})

      assert meta["author"] == b62(ctx.author)
      assert meta["tags"] == ["elixir"]
      assert meta["reactions"] == ["LIKE"]
      assert meta["mentions"] == ["someone-else"]
    end

    test "a family the clump has blocked takes only its own list", ctx do
      ctx = with_payload(ctx, %{})
      entry = {b62(ctx.author), ctx.log_id, ctx.seq}

      with_index(:tags, entry, [{100, "elixir"}])
      with_index(:reactions, entry, [{101, "LIKE"}])

      tag_log = List.first(QuaggaDef.logs_for_name(:tag))
      # A full-mask pattern matches this one log id and nothing else, and
      # unlike `block/2` it purges no entries to prove it took effect.
      block_pattern(ctx, %{op: :eq, mask: 0xFFFFFFFFFFFFFFFF, v: tag_log})

      assert {:ok, meta} =
               AppHost.handle(ctx.app, "entry_meta", %{log_id: ctx.log_id, seq: ctx.seq})

      assert meta["tags"] == []
      assert meta["reactions"] == ["LIKE"]
    end

    test "the reference lists ride along with the relations", ctx do
      ctx = with_payload(ctx, %{"references" => []})
      ctx = with_payload(ctx, %{"references" => [[ctx.author, ctx.log_id, 1]]})

      entry = {b62(ctx.author), ctx.log_id, ctx.seq}
      with_index(:references, entry, [{10, {b62(ctx.author), ctx.log_id, 2}}])

      assert {:ok, meta} =
               AppHost.handle(ctx.app, "entry_meta", %{log_id: ctx.log_id, seq: ctx.seq})

      assert meta["back-refs"] == [[b62(ctx.author), ctx.log_id, 1]]
      assert meta["refs"] == [{b62(ctx.author), ctx.log_id, 2}]
      assert meta["fore-refs"] == []
    end

    test "a blocked entry is refused rather than answered", ctx do
      ctx = with_payload(ctx, %{})
      base = Bitwise.band(ctx.log_id, @base_mask)
      block_pattern(ctx, %{op: :eq, mask: @base_mask, v: base})

      assert {:error, :blocked} =
               AppHost.handle(ctx.app, "entry_meta", %{log_id: ctx.log_id, seq: ctx.seq})
    end

    test "incomplete or malformed arguments are refused", ctx do
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "entry_meta", %{})
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "entry_meta", %{log_id: 1})
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "entry_meta", %{seq: 1})
    end
  end

  describe "timeline" do
    # The index is written oldest-first and an app shows a timeline the
    # other way round, so the newest entry is the head of the page.
    test "an identity's timeline comes back newest first", ctx do
      author = Catenary.id_for_key(Preferences.get(:identity))
      log_id = List.first(QuaggaDef.logs_for_name(:journal))

      with_index(:timelines, b62(author), [
        {100, {b62(author), log_id, 1}},
        {200, {b62(author), log_id, 2}},
        {300, {b62(author), log_id, 3}}
      ])

      assert {:ok, entries} = AppHost.handle(ctx.app, "timeline", %{})

      assert Enum.map(entries, & &1["seq"]) == [3, 2, 1]
      assert hd(entries)["author"] == b62(author)
      assert hd(entries)["published"] == 300
    end

    test "a kind keeps only the logs that family owns", ctx do
      author = Catenary.id_for_key(Preferences.get(:identity))
      journal = List.first(QuaggaDef.logs_for_name(:journal))
      reply = List.first(QuaggaDef.logs_for_name(:reply))

      with_index(:timelines, b62(author), [
        {100, {b62(author), journal, 1}},
        {200, {b62(author), reply, 2}}
      ])

      assert {:ok, [%{"seq" => 2}]} =
               AppHost.handle(ctx.app, "timeline", %{kind: "reply"})

      assert {:ok, [%{"seq" => 1}]} =
               AppHost.handle(ctx.app, "timeline", %{kind: "journal"})

      assert {:ok, [%{"seq" => 2}, %{"seq" => 1}]} =
               AppHost.handle(ctx.app, "timeline", %{kind: "all"})
    end

    test "the cursor counts entries back from the newest", ctx do
      author = Catenary.id_for_key(Preferences.get(:identity))
      log_id = List.first(QuaggaDef.logs_for_name(:journal))

      with_index(:timelines, b62(author), [
        {100, {b62(author), log_id, 1}},
        {200, {b62(author), log_id, 2}},
        {300, {b62(author), log_id, 3}}
      ])

      assert {:ok, [%{"seq" => 3}]} =
               AppHost.handle(ctx.app, "timeline", %{limit: 1})

      assert {:ok, [%{"seq" => 2}]} =
               AppHost.handle(ctx.app, "timeline", %{cursor: 1, limit: 1})

      assert {:ok, []} = AppHost.handle(ctx.app, "timeline", %{cursor: 5})
    end

    test "a blocked entry leaves the page rather than taking a place on it", ctx do
      author = Catenary.id_for_key(Preferences.get(:identity))
      journal = List.first(QuaggaDef.logs_for_name(:journal))
      reply = List.first(QuaggaDef.logs_for_name(:reply))

      with_index(:timelines, b62(author), [
        {100, {b62(author), journal, 1}},
        {200, {b62(author), journal, 2}},
        {300, {b62(author), reply, 3}}
      ])

      # The mask the viewer blocks with: it names this one log id, and
      # unlike `block/2` it purges no entries to prove it took effect.
      block_pattern(ctx, %{op: :eq, mask: @base_mask, v: Bitwise.band(journal, @base_mask)})

      assert {:ok, entries} = AppHost.handle(ctx.app, "timeline", %{})
      assert Enum.map(entries, & &1["seq"]) == [3]

      assert {:ok, [%{"seq" => 3}]} =
               AppHost.handle(ctx.app, "timeline", %{limit: 1})
    end

    test "an author the clump refuses is refused outright", ctx do
      Baobab.ClumpMeta.block(@foreign_author, ctx.clump_id)
      on_exit(fn -> Baobab.ClumpMeta.unblock(@foreign_author, ctx.clump_id) end)

      assert {:error, :blocked} =
               AppHost.handle(ctx.app, "timeline", %{author: @foreign_author})
    end

    test "an author with no timeline answers with an empty page", ctx do
      assert {:ok, []} = AppHost.handle(ctx.app, "timeline", %{author: @foreign_author})
    end

    test "incomplete or malformed arguments are refused", ctx do
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "timeline", %{kind: "listing"})
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "timeline", %{cursor: -1})
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "timeline", %{limit: -1})
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "timeline", %{author: "nonsense"})
    end
  end

  describe "profile" do
    test "the name this identity gave a key rides beside what they wrote", ctx do
      author = Catenary.id_for_key(Preferences.get(:identity))

      with_index(:about, b62(author), %{
        "name" => "Catenary",
        "description" => "A social index for the quiet corners"
      })

      previous = Catenary.State.get(:aliases) || %{}
      on_exit(fn -> Catenary.State.set_aliases(previous) end)
      Catenary.State.set_aliases(Map.put(previous, b62(author), "me"))

      assert {:ok, profile} = AppHost.handle(ctx.app, "profile", %{author: b62(author)})

      assert profile["author"] == b62(author)
      assert profile["alias"] == "me"
      assert profile["about"]["name"] == "Catenary"
      assert profile["about"]["description"] == "A social index for the quiet corners"
    end

    test "an identity nobody named that said nothing answers plainly", ctx do
      assert {:ok, profile} = AppHost.handle(ctx.app, "profile", %{author: @foreign_author})

      assert profile == %{"author" => @foreign_author, "alias" => nil, "about" => nil}
    end

    test "with no author named it answers the app's own profile", ctx do
      author = b62(Catenary.id_for_key(Preferences.get(:identity)))

      assert {:ok, profile} = AppHost.handle(ctx.app, "profile", %{})

      assert profile["author"] == author
    end

    test "a blocked author is refused", ctx do
      Baobab.ClumpMeta.block(@foreign_author, ctx.clump_id)
      on_exit(fn -> Baobab.ClumpMeta.unblock(@foreign_author, ctx.clump_id) end)

      assert {:error, :blocked} =
               AppHost.handle(ctx.app, "profile", %{author: @foreign_author})
    end

    test "malformed arguments are refused", ctx do
      assert {:error, :bad_args} = AppHost.handle(ctx.app, "profile", %{author: "nonsense"})
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
