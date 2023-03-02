defmodule Catenary.Indices do
  require Logger

  @moduledoc """
  Functions to recompute indices

  There is no sense in having stateful gen_servers

  for these.  We have no idea what to do if we fail.
  """

  # about is in another castle.  also avatars
  # This... sucks.
  @tables [:references, :tags, :reactions, :aliases, :timelines, :mentions, :about, :avatars]
  @table_options [:public, :named_table]

  def reset() do
    # This information is all over the place. :(
    # One source of truth
    empty_tables(@tables)
  end

  defp empty_tables([]), do: :ok

  defp empty_tables([curr | rest]) do
    case curr in :ets.all() do
      true -> :ets.delete_all_objects(curr)
      false -> :ets.new(curr, @table_options)
    end

    empty_tables(rest)
  end

  @logs_for_table %{
    references: QuaggaDef.logs_for_encoding(:cbor),
    tags: QuaggaDef.logs_for_name(:tag),
    reactions: QuaggaDef.logs_for_name(:react),
    timelines:
      Enum.reduce(Catenary.timeline_logs(), [], fn n, a -> a ++ QuaggaDef.logs_for_name(n) end)
  }

  def update_index(which, stored_info, clump_id, inform \\ nil) do
    {hash, logs} = pick_logs(stored_info, @logs_for_table[which])

    case :ets.lookup(which, :prev_hash) do
      [{:prev_hash, ^hash}] ->
        :ok

      _ ->
        index(logs, clump_id, which, inform)
        :ets.insert(which, {:prev_hash, hash})
    end
  end

  defp pick_logs(logs, matches) do
    set = Enum.filter(logs, fn {_, l, _} -> l in matches end)
    {set |> :erlang.term_to_binary() |> Blake2.hash2b(), set}
  end

  defp index([], cid, which, inform) when is_pid(inform) do
    # Sometimes we finish while the process is still in startup
    # Process does an async send and does not ensure that it arrives in
    # the mailbox.  We'll just make sure it's in its standard running state 
    # before sending.  This can suck if it's busy, but these can usually wait
    status = Process.info(inform)

    case is_list(status) and Keyword.get(status, :current_function) do
      {:gen_server, :loop, _} ->
        Process.send(inform, {:completed, {:indexing, which, self()}}, [])

      _ ->
        Process.sleep(59)
        index([], cid, which, inform)
    end
  end

  defp index([], _, _, _), do: :ok

  defp index([{a, l, _} | rest], clump_id, which, inform) do
    entries_index(Baobab.full_log(a, log_id: l, clump_id: clump_id), clump_id, which)
    index(rest, clump_id, which, inform)
  end

  # This could maybe give up on a CBOR failure, eventually
  # Right now we have a lot of mixed types
  defp entries_index([], _, _), do: :ok

  defp entries_index([entry | rest], clump_id, :timelines) do
    try do
      %Baobab.Entry{author: a, log_id: l, seqnum: s, payload: payload} = entry
      ident = Baobab.Identity.as_base62(a)
      {:ok, data, ""} = CBOR.decode(payload)

      old =
        case :ets.lookup(:timelines, ident) do
          [] -> []
          [{^ident, val}] -> val
        end

      insert = [{published(data), {ident, l, s}} | old] |> Enum.sort() |> Enum.uniq()

      :ets.insert(:timelines, {ident, insert})
    rescue
      _ -> :ok
    end

    entries_index(rest, clump_id, :timelines)
  end

  defp entries_index([entry | rest], clump_id, :tags) do
    # This is a two-way index
    try do
      %Baobab.Entry{payload: payload} = entry
      {:ok, data, ""} = CBOR.decode(payload)
      tags = data["tags"] |> Enum.map(fn s -> {"", String.trim(s)} end)
      [ent] = data["references"]
      e = List.to_tuple(ent)
      # Tags for entry
      old =
        case :ets.lookup(:tags, e) do
          [] -> []
          [{^e, val}] -> val
        end

      into = (old ++ tags) |> Enum.sort() |> Enum.uniq()
      :ets.insert(:tags, {e, into})

      # Entries for tag
      for tag <- tags do
        old_val =
          case :ets.lookup(:tags, tag) do
            [] -> []
            [{^tag, val}] -> val
          end

        insert =
          [{published(data), e} | old_val] |> Enum.sort() |> Enum.uniq_by(fn {_p, e} -> e end)

        :ets.insert(:tags, {tag, insert})
      end
    rescue
      _ -> :ok
    end

    entries_index(rest, clump_id, :tags)
  end

  defp entries_index([entry | rest], clump_id, :mentions) do
    # This is a two-way index
    try do
      %Baobab.Entry{payload: payload} = entry
      {:ok, data, ""} = CBOR.decode(payload)
      mentions = data["mentions"] |> Enum.map(fn s -> {"", String.trim(s)} end)
      [ent] = data["references"]
      e = List.to_tuple(ent)
      # Mentions for entry
      old =
        case :ets.lookup(:mentions, e) do
          [] -> []
          [{^e, val}] -> val
        end

      into = (old ++ mentions) |> Enum.sort() |> Enum.uniq()
      :ets.insert(:mentions, {e, into})

      # Entries for mentioned
      for mention <- mentions do
        old_val =
          case :ets.lookup(:mentions, mention) do
            [] -> []
            [{^mention, val}] -> val
          end

        insert =
          [{published(data), e} | old_val] |> Enum.sort() |> Enum.uniq_by(fn {_p, e} -> e end)

        :ets.insert(:mentions, {mention, insert})
      end
    rescue
      _ -> :ok
    end

    entries_index(rest, clump_id, :mentions)
  end

  defp entries_index([entry | rest], clump_id, :reactions) do
    try do
      %Baobab.Entry{payload: payload} = entry
      {:ok, data, ""} = CBOR.decode(payload)
      reacts = data["reactions"] |> Enum.map(fn s -> {"", s} end)
      [ent] = data["references"]
      e = List.to_tuple(ent)

      old =
        case :ets.lookup(:reactions, e) do
          [] -> []
          [{^e, val}] -> val
        end

      # This might eventually have log-scale counting
      into = (old ++ reacts) |> Enum.sort() |> Enum.uniq()
      :ets.insert(:reactions, {e, into})
    rescue
      _ -> :ok
    end

    entries_index(rest, clump_id, :reactions)
  end

  defp entries_index([%Baobab.Entry{author: a} = entry | rest], clump_id, :aliases) do
    # We map aliases for all of our identities, not just the
    # one we care currently using.  Meh.
    me = Baobab.Identity.list() |> Enum.map(fn {_n, k} -> k end)

    case Baobab.Identity.as_base62(a) in me do
      true ->
        try do
          %Baobab.Entry{payload: payload} = entry
          {:ok, data, ""} = CBOR.decode(payload)
          :ets.match_delete(:aliases, {:_, data["alias"]})
          :ets.insert(:aliases, {data["whom"], data["alias"]})
        rescue
          _ ->
            :ok
        end

      false ->
        :ok
    end

    entries_index(rest, clump_id, :aliases)
  end

  defp entries_index([entry | rest], clump_id, :references) do
    try do
      %Baobab.Entry{author: a, log_id: l, seqnum: s, payload: payload} = entry
      index = {Baobab.Identity.as_base62(a), l, s}
      {:ok, data, ""} = CBOR.decode(payload)

      for lref <- Map.get(data, "references") do
        tref = lref |> List.to_tuple()

        old_val =
          case :ets.lookup(:references, tref) do
            [] -> []
            [{^tref, val}] -> val
          end

        new_val = (old_val ++ [{published(data), index}]) |> Enum.sort() |> Enum.uniq()

        :ets.insert(:references, {tref, new_val})
      end
    rescue
      _ ->
        :ok
    end

    entries_index(rest, clump_id, :references)
  end

  defp published(data) when is_map(data) do
    case data["published"] do
      nil ->
        ""

      t ->
        t
        |> Timex.parse!("{ISO:Extended}")
        |> Timex.to_unix()
    end
  end

  defp published(_), do: ""
end
