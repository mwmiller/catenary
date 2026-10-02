defmodule Catenary.AppHost do
  @moduledoc """
  The single choke point every app-facing host operation goes through.

  An app never reads the spool, the index tables or the filter preferences
  directly. It sends an operation name with some arguments and this module
  decides whether to answer, applying the same visibility rules the
  viewer's own UI applies. An operation added anywhere else would reach
  local data without those rules, so there is deliberately only this one
  door.

  Two things belong to the caller rather than to this module:

    * **Building `app`.** The context names which listing is running
      (`pk`, `slug`) and which store it runs against (`clump_id`). The
      LiveView must assemble it from its own assigns, never from anything
      a worker sent, or an app could widen its scope into another app's
      keys.

    * **Transport.** `handle/3` returns Elixir terms, and payload bytes
      are returned as a `CBOR.Tag` rather than a bare binary: Elixir
      encodes a plain binary as a CBOR *text* string, which would put an
      arbitrary log payload through a UTF-8 conversion on its way to the
      worker. The bridge that puts a reply on the wire just encodes what
      comes back from here.
  """

  alias Catenary.AppKV

  @type app :: %{clump_id: String.t(), pk: binary, slug: String.t()}

  # The operation allow-list. Matching on the names themselves rather than
  # turning a wire string into an atom means an unrecognised operation
  # never creates an atom and never reaches a read.
  @ops ~w(log_read log_head log_range refs entry_meta timeline profile storage_get
         storage_set)

  # A range answers with a page, not with a log: at most this many entries
  # and at most this much payload, whichever comes first. The first visible
  # entry is always taken whole, so one oversized entry still arrives rather
  # than the page coming back empty.
  @max_range 64
  @max_range_bytes 256 * 1024
  @default_range 8

  # The same rule for the lists an entry is part of: one entry referenced a
  # thousand times still answers with what fits, rather than with a reply as
  # large as the store is.
  @max_relations 256

  @doc """
  Every operation this host answers to. Anything else is refused without
  a lookup, which is what makes `handle/3` a boundary rather than a
  convenience wrapper.
  """
  @spec ops() :: [String.t()]
  def ops, do: @ops

  @doc """
  Build the app context from server-side state.
  """
  @spec app(String.t(), binary, String.t()) :: app
  def app(clump_id, pk, slug)
      when is_binary(clump_id) and is_binary(pk) and is_binary(slug),
      do: %{clump_id: clump_id, pk: pk, slug: slug}

  @doc """
  Run one host operation for `app`, named by `op`.

  Returns `{:ok, value}` or `{:error, reason}`. Being blocked, missing or
  unsupported is an answer the app has to handle rather than a crash: the
  worker keeps running either way.
  """
  @spec handle(app, String.t(), map) :: {:ok, term} | {:error, term}
  def handle(app, op, args) when is_binary(op) and is_map(args) do
    case app do
      %{clump_id: c, pk: p, slug: s} when is_binary(c) and is_binary(p) and is_binary(s) ->
        dispatch(app, op, args)

      _ ->
        {:error, :bad_app}
    end
  end

  # A malformed message is an error the caller can report, not a reason to
  # take the LiveView down: this function is reachable from the wire.
  def handle(_app, _op, _args), do: {:error, :bad_args}

  # One clause per advertised operation, so the names this host answers are
  # readable down the left margin and anything else is refused without a
  # lookup.
  defp dispatch(app, "log_read", args), do: log_read(app, args)
  defp dispatch(app, "log_head", args), do: log_head(app, args)
  defp dispatch(app, "log_range", args), do: log_range(app, args)
  defp dispatch(app, "refs", args), do: refs(app, args)
  defp dispatch(app, "entry_meta", args), do: entry_meta(app, args)
  defp dispatch(app, "timeline", args), do: timeline(app, args)
  defp dispatch(app, "profile", args), do: profile(app, args)
  defp dispatch(app, "storage_get", args), do: storage_get(app, args)
  defp dispatch(app, "storage_set", args), do: storage_set(app, args)
  defp dispatch(_app, _op, _args), do: {:error, :unsupported_op}

  # The author an app means when it does not name one: itself. A draft runs
  # as the identity that wrote it and a published app as its publisher, and
  # both are keys this host already holds — naming them back would be
  # ceremony the module cannot get wrong.
  defp resolve_author(app, args) do
    case arg(args, :author) do
      :error -> as_author(app.pk)
      {:ok, author} -> as_author(author)
    end
  end

  defp log_read(%{clump_id: clump_id} = app, args) do
    with {:ok, author} <- resolve_author(app, args),
         {:ok, log_id} <- arg(args, :log_id),
         {:ok, seq} <- arg(args, :seq),
         {:ok, log_id} <- as_log_id(log_id),
         {:ok, seq} <- as_seq(seq),
         :ok <- visible(author, log_id, seq, clump_id),
         {:ok, payload} <- fetch(author, log_id, seq, clump_id) do
      {:ok, payload}
    else
      :error -> {:error, :bad_args}
      {:error, _} = err -> err
    end
  end

  # The newest sequence number on a log: what a module needs before it asks
  # for a range, and the cheapest answer the store can give about a log that
  # may hold nothing at all.
  defp log_head(app, args) do
    with {:ok, author} <- resolve_author(app, args),
         {:ok, log_id} <- arg(args, :log_id),
         {:ok, log_id} <- as_log_id(log_id),
         {:ok, seq} <- head(author, log_id, app.clump_id),
         :ok <- visible(author, log_id, seq, app.clump_id) do
      {:ok, %{"seq" => seq}}
    else
      :error -> {:error, :bad_args}
      {:error, _} = err -> err
    end
  end

  defp head(author, log_id, clump_id) do
    case Baobab.max_seqnum(author, log_id: log_id, clump_id: clump_id) do
      0 -> {:error, :missing}
      seq -> {:ok, seq}
    end
  end

  defp log_range(app, args) do
    with {:ok, author} <- resolve_author(app, args),
         {:ok, log_id} <- arg(args, :log_id),
         {:ok, log_id} <- as_log_id(log_id),
         {:ok, from} <- arg(args, :from, 1),
         {:ok, from} <- as_at(from),
         {:ok, count} <- arg(args, :count, @default_range),
         {:ok, count} <- as_count(count) do
      page(app.clump_id, author, log_id, from, count)
    else
      # Every branch above can only fail this one way. `page/5` sits in the
      # body rather than in a branch, so its own refusals leave untouched.
      :error -> {:error, :bad_args}
    end
  end

  # Seqs the store does not hold are simply not on the page, so a gap reads
  # as an absence rather than as a failure of the whole range.
  defp page(clump_id, author, log_id, from, count) do
    seqs =
      author
      |> Baobab.all_seqnum(log_id: log_id, clump_id: clump_id)
      |> Enum.drop_while(&(&1 < from))

    with {:ok, visible} <- visible_seqs(author, log_id, seqs, clump_id) do
      {:ok, fetch_page(author, log_id, clump_id, Enum.take(visible, count), 0, [])}
    end
  end

  # The store answers "which of these may be seen" in one pass, so a blocked
  # range costs the same call an unblocked one does.
  defp visible_seqs(_author, _log_id, [], _clump_id), do: {:ok, []}

  defp visible_seqs(author, log_id, seqs, clump_id) do
    case Baobab.ClumpMeta.filter_blocked(Enum.map(seqs, &{author, log_id, &1}), clump_id) do
      {:error, _} = err -> err
      kept -> {:ok, Enum.map(kept, fn {_, _, seq} -> seq end)}
    end
  end

  defp fetch_page(_author, _log_id, _clump_id, [], _budget, acc), do: Enum.reverse(acc)

  defp fetch_page(author, log_id, clump_id, [seq | rest], budget, acc) do
    case Baobab.log_entry(author, seq, log_id: log_id, clump_id: clump_id) do
      %Baobab.Entry{payload: payload} ->
        reply = %{"seq" => seq, "payload" => %CBOR.Tag{tag: :bytes, value: payload}}
        size = byte_size(payload)

        # Always take the first one whole, then whole entries while the page
        # has room: half an entry would not decode and a refused first entry
        # would answer with nothing.
        if acc == [] or budget + size <= @max_range_bytes do
          fetch_page(author, log_id, clump_id, rest, budget + size, [reply | acc])
        else
          Enum.reverse(acc)
        end

      _ ->
        fetch_page(author, log_id, clump_id, rest, budget, acc)
    end
  end

  # An entry read for what it is rather than for what it says: the same
  # three arguments as `log_read`, the same visibility check, and the
  # payload only so an entry's own references can be read out of it. `:max`
  # names the newest entry rather than a number, so it is resolved before
  # anything is checked or looked up.
  defp reference_entry(app, args) do
    with {:ok, author} <- resolve_author(app, args),
         {:ok, log_id} <- arg(args, :log_id),
         {:ok, seq} <- arg(args, :seq),
         {:ok, log_id} <- as_log_id(log_id),
         {:ok, seq} <- as_seq(seq),
         {:ok, seq} <- newest(author, log_id, seq, app.clump_id),
         :ok <- visible(author, log_id, seq, app.clump_id),
         {:ok, %CBOR.Tag{value: payload}} <- fetch(author, log_id, seq, app.clump_id) do
      {:ok, {author, log_id, seq}, payload}
    else
      :error -> {:error, :bad_args}
      {:error, _} = err -> err
    end
  end

  defp newest(_author, _log_id, seq, _clump_id) when is_integer(seq), do: {:ok, seq}
  defp newest(author, log_id, :max, clump_id), do: head(author, log_id, clump_id)

  # What an entry names, and what names it — the three lists an entry's
  # metabox shows. `back-refs` come out of the payload; the other two come
  # from the index of incoming references, split on reply logs the way the
  # viewer splits them, so answering is a table read rather than a walk over
  # a log looking for whoever pointed here.
  defp refs(app, args) do
    with {:ok, entry, payload} <- reference_entry(app, args) do
      {:ok, reference_lists(entry, payload)}
    end
  end

  # The whole metabox: the entry's author and every relation held against
  # it. Each list is gated on its own family the way the viewer gates it, so
  # blocking a family takes that list out of the answer without taking the
  # rest of the entry with it.
  defp entry_meta(app, args) do
    with {:ok, {author, _log_id, _seq} = entry, payload} <- reference_entry(app, args) do
      {:ok,
       reference_lists(entry, payload)
       |> Map.merge(%{
         "author" => author,
         "tags" => relation(entry, :tags, :tag, app.clump_id),
         "reactions" => relation(entry, :reactions, :react, app.clump_id),
         "mentions" => relation(entry, :mentions, :mention, app.clump_id)
       })}
    end
  end

  defp reference_lists(entry, payload) do
    reply_logs = QuaggaDef.logs_for_name(:reply)

    {fore, plain} =
      entry
      |> rows(:references)
      |> Enum.split_with(fn {_author, log_id, _seq} -> log_id in reply_logs end)

    %{
      "back-refs" => back_refs(payload),
      "refs" => Enum.take(plain, @max_relations),
      "fore-refs" => Enum.take(fore, @max_relations)
    }
  end

  # One relation: from the index table holding {published, value} rows for
  # this entry, and only while the family it comes from is still wanted. The
  # published date belongs to the viewer's ordering, not to this answer.
  defp relation(entry, table, family, clump_id) do
    case allowed?(family, clump_id) do
      true -> entry |> rows(table) |> Enum.take(@max_relations)
      false -> []
    end
  end

  # The viewer asks its own preferences whether a relation family is still
  # wanted; an app gets the same answer computed from the clump it runs
  # against, so the gate does not move with a setting an app never sees. An
  # error from the store reads as allowed, because `reference_entry/2` has
  # already refused a clump the store does not know.
  defp allowed?(family, clump_id) do
    case QuaggaDef.logs_for_name(family) do
      [] -> true
      [log_id | _] -> Baobab.ClumpMeta.blocked?(log_id, clump_id) != true
    end
  end

  # The index tables key an entry as {author, log_id, seq} and hold
  # {published, value} rows under it. A table the workers have not built yet
  # answers with nothing rather than raising: an app is asking about an
  # entry, not about the state of the local index.
  defp rows(entry, table) do
    with true <- :ets.whereis(table) != :undefined,
         [{^entry, found}] <- :ets.lookup(table, entry) do
      Enum.map(found, fn {_published, value} -> value end)
    else
      _ -> []
    end
  end

  # An entry's own references, read from the payload it carries. The list is
  # whatever the writer put there, so anything an app could not use is
  # dropped rather than passed on as something it would have to defend
  # against: a name that resolves to no identity is not a reference.
  defp back_refs(payload) do
    case decode(payload) do
      {:ok, %{"references" => list}} when is_list(list) ->
        list |> Enum.flat_map(&as_ref/1) |> Enum.take(@max_relations)

      _ ->
        []
    end
  end

  defp decode(payload) do
    with {:ok, value, _rest} <- CBOR.decode(payload), do: {:ok, value}
  rescue
    _ -> :error
  end

  defp as_ref([author, log_id, seq]) when is_integer(log_id) and is_integer(seq) do
    case as_author(author) do
      {:ok, author} -> [[author, log_id, seq]]
      :error -> []
    end
  end

  defp as_ref(_), do: []

  # An identity's timeline — what they wrote, newest first, out of the index
  # that already holds it per author rather than out of a scan over logs.
  # `cursor` counts entries back from the newest one, so 0 is the head of
  # the timeline and a larger cursor walks backwards through it: the same
  # list the viewer steps along, only sliced for a page instead of walked.
  defp timeline(app, args) do
    with {:ok, author} <- resolve_author(app, args),
         :ok <- author_visible(author, app.clump_id),
         {:ok, family} <- arg(args, :kind, :all),
         {:ok, logs} <- as_kind(family),
         {:ok, cursor} <- arg(args, :cursor, 0),
         {:ok, cursor} <- as_cursor(cursor),
         {:ok, limit} <- arg(args, :limit, @default_range),
         {:ok, limit} <- as_count(limit) do
      author
      |> timeline_rows(logs)
      |> timeline_page(app.clump_id, cursor, limit)
    else
      :error -> {:error, :bad_args}
      {:error, _} = err -> err
    end
  end

  # The page itself: what the clump will show, sliced from the newest entry
  # back. Filtering comes before the offset so an entry that may not be
  # shown does not take a place on the page.
  defp timeline_page(rows, clump_id, cursor, limit) do
    with {:ok, kept} <- visible_entries(Enum.map(rows, &elem(&1, 1)), clump_id) do
      published = Map.new(rows, fn {unix, entry} -> {entry, unix} end)

      {:ok,
       kept
       |> Enum.drop(cursor)
       |> Enum.take(limit)
       |> Enum.map(&timeline_entry(&1, published))}
    end
  end

  defp timeline_entry({writer, log_id, seq} = entry, published) do
    %{
      "author" => writer,
      "log_id" => log_id,
      "seq" => seq,
      "published" => Map.fetch!(published, entry)
    }
  end

  # What a profile is made of here: the name *this* identity gave a key,
  # and what that key wrote about itself. They are separate answers because
  # an alias is local — the index folds the active identity's own alias log
  # and no other, so this is the name the user's own UI shows and nothing
  # when they never gave one, rather than a claim about how anybody else
  # spells the key. `author` defaults to the app's own key like everywhere
  # else: a module is written before it has a key to name.
  defp profile(app, args) do
    with {:ok, author} <- resolve_author(app, args),
         :ok <- author_visible(author, app.clump_id) do
      {:ok, %{"author" => author, "alias" => local_alias(author), "about" => about(author)}}
    else
      :error -> {:error, :bad_args}
      {:error, _} = err -> err
    end
  end

  defp local_alias(author) do
    case Catenary.State.get(:aliases) do
      aliases when is_map(aliases) -> Map.get(aliases, author)
      _ -> nil
    end
  end

  # The key's own `about` entry as the index folded it: whatever they said
  # about themselves, under the author key. `null` is an identity that has
  # written no `about` entry this store knows of.
  defp about(author) do
    with true <- :ets.whereis(:about) != :undefined,
         [{^author, described}] <- :ets.lookup(:about, author) do
      described
    else
      _ -> nil
    end
  end

  # An author the clump refuses is refused outright rather than answered
  # with an empty page: their timeline may not be shown, which is not the
  # same as their having written nothing.
  defp author_visible(author, clump_id) do
    case Baobab.ClumpMeta.blocked?(author, clump_id) do
      true -> {:error, :blocked}
      _ -> :ok
    end
  end

  # `kind` names the family a timeline log belongs to — `journal` or
  # `reply` — and `all` means every log an identity's timeline is made of.
  # A family with no timeline of its own is a mistake rather than a page
  # that happens to be empty.
  defp as_kind(kind) when kind in ["all", :all, nil], do: {:ok, timeline_logs()}

  defp as_kind(kind) when kind in ["journal", :journal],
    do: {:ok, QuaggaDef.logs_for_name(:journal)}

  defp as_kind(kind) when kind in ["reply", :reply], do: {:ok, QuaggaDef.logs_for_name(:reply)}
  defp as_kind(_), do: :error

  defp timeline_logs do
    Enum.flat_map(Catenary.timeline_logs(), &QuaggaDef.logs_for_name/1)
  end

  # The index holds {published, entry} rows under the writer's base62 name,
  # oldest first; a timeline is that list in the order an app shows it,
  # with the logs this `kind` did not ask for already dropped. A table the
  # workers have not built yet is an empty timeline.
  defp timeline_rows(author, logs) do
    with true <- :ets.whereis(:timelines) != :undefined,
         [{^author, rows}] <- :ets.lookup(:timelines, author) do
      rows
      |> Enum.filter(fn {_, {_writer, log_id, _seq}} -> log_id in logs end)
      |> Enum.reverse()
    else
      _ -> []
    end
  end

  defp visible_entries([], _clump_id), do: {:ok, []}

  defp visible_entries(entries, clump_id) do
    case Baobab.ClumpMeta.filter_blocked(entries, clump_id) do
      {:error, _} = err -> err
      kept -> {:ok, kept}
    end
  end

  # A cursor counts entries back from the newest one; there is no position
  # before the beginning of a timeline.
  defp as_cursor(cursor) when is_integer(cursor) and cursor >= 0, do: {:ok, cursor}
  defp as_cursor(_), do: :error

  defp storage_get(app, args) do
    case arg(args, :key) do
      {:ok, key} when is_binary(key) -> AppKV.get(app, key)
      _ -> {:error, :bad_args}
    end
  end

  defp storage_set(app, args) do
    with {:ok, key} when is_binary(key) <- arg(args, :key),
         {:ok, value} <- arg(args, :value) do
      :ok = AppKV.put(app, key, value)
      {:ok, :stored}
    else
      _ -> {:error, :bad_args}
    end
  end

  # One check covers everything that decides whether an entry may be seen:
  # literal author, log and {author, log} blocks, the base-log pattern
  # blocks `Catenary.BlockLog.block_name/2` writes, and the family pattern
  # blocks `Catenary.BlockLog.block_family/2` writes. It is the same
  # classifier the rest of the app filters a list of entries with, which is
  # what keeps an app from seeing something the viewer would hide.
  defp visible(author, log_id, seq, clump_id) do
    case Baobab.ClumpMeta.filter_blocked([{author, log_id, seq}], clump_id) do
      [_entry] -> :ok
      [] -> {:error, :blocked}
      # A clump the store does not know. Passing it through rather than
      # reading it as `false` keeps an unusable context from being taken
      # for a permission grant.
      {:error, _} = err -> err
    end
  end

  defp fetch(author, log_id, seq, clump_id) do
    case Baobab.log_entry(author, seq, log_id: log_id, clump_id: clump_id) do
      %Baobab.Entry{payload: payload} -> {:ok, %CBOR.Tag{tag: :bytes, value: payload}}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :missing}
    end
  end

  # Blocks are recorded against the base62 form of an author, so an author
  # given as an alias name or a raw key has to be normalised before it is
  # compared against them. Without this an app could sidestep an author
  # block simply by naming the author differently than the block does.
  defp as_author(author) when is_binary(author) and author != "" do
    case Baobab.Identity.as_base62(author) do
      {:error, _} -> :error
      base62 -> {:ok, base62}
    end
  end

  defp as_author(_), do: :error

  defp as_log_id(log_id) when is_integer(log_id) and log_id >= 0, do: {:ok, log_id}
  defp as_log_id(_), do: :error

  defp as_seq(seq) when is_integer(seq) and seq > 0, do: {:ok, seq}
  defp as_seq("max"), do: {:ok, :max}
  defp as_seq(:max), do: {:ok, :max}
  defp as_seq(_), do: :error

  # Arguments arrive from the worker as JSON, so their keys are strings,
  # while internal callers use atoms. Both are accepted; a key from the
  # wire is never turned into an atom.
  defp arg(args, key) when is_atom(key) do
    case Map.fetch(args, key) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(args, Atom.to_string(key))
    end
  end

  # An argument an op can do without: absent means the default, present
  # means whatever it carries, unusable or not.
  defp arg(args, key, default) when is_atom(key) do
    case arg(args, key) do
      :error -> {:ok, default}
      found -> found
    end
  end

  defp as_at(seq) when is_integer(seq) and seq > 0, do: {:ok, seq}
  defp as_at(_), do: :error

  # Asking for more than a page holds is not an error: the answer is one
  # page either way, and a module that overshot still gets what fits.
  defp as_count(count) when is_integer(count) and count >= 0, do: {:ok, min(count, @max_range)}
  defp as_count(_), do: :error
end
