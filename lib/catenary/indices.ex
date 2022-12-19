defmodule Catenary.Indices do
  require Logger

  @moduledoc """
  Functions to recompute indices

  There is no sense in having stateful gen_servers

  for these.  We have no idea what to do if we fail.
  """

  def clear_all() do
    # This information is all over the place. :(
    # One source of truth
    for table <- [:references, :tags, :reactions, :aliases, :timelines] do
      Catenary.dets_open(table)
      :dets.delete_all_objects(table)
      Catenary.dets_close(table)
    end
  end

  def index_references(stored_info, clump_id) do
    {hash, logs} = pick_logs(stored_info, QuaggaDef.logs_for_encoding(:cbor))
    Catenary.dets_open(:references)

    case :dets.lookup(:references, :prev_hash) do
      [{:prev_hash, ^hash}] ->
        :ok

      _ ->
        index(logs, clump_id, :references)
        :dets.insert(:references, {:prev_hash, hash})
    end

    Catenary.dets_close(:references)
  end

  def index_aliases(id, clump_id) do
    alias_logs = QuaggaDef.logs_for_name(:alias)
    Catenary.dets_open(:aliases)
    :dets.delete_all_objects(:aliases)

    alias_logs
    |> Enum.map(fn l -> {id, l, 1} end)
    |> index(clump_id, :aliases)

    Catenary.dets_close(:aliases)
  end

  def index_tags(stored_info, clump_id) do
    {hash, logs} = pick_logs(stored_info, QuaggaDef.logs_for_name(:tag))
    Catenary.dets_open(:tags)

    case :dets.lookup(:tags, :prev_hash) do
      [{:prev_hash, ^hash}] ->
        :ok

      _ ->
        index(logs, clump_id, :tags)
        :dets.insert(:tags, {:prev_hash, hash})
    end

    index(logs, clump_id, :tags)
    Catenary.dets_close(:tags)
  end

  def index_reactions(stored_info, clump_id) do
    {hash, logs} = pick_logs(stored_info, QuaggaDef.logs_for_name(:react))
    Catenary.dets_open(:reactions)

    case :dets.lookup(:reactions, :prev_hash) do
      [{:prev_hash, ^hash}] ->
        :ok

      _ ->
        index(logs, clump_id, :reactions)
        :dets.insert(:reactions, {:prev_hash, hash})
    end

    index(stored_info, clump_id, :reactions)
    Catenary.dets_close(:reactions)
  end

  def index_timelines(stored_info, clump_id) do
    {hash, logs} =
      pick_logs(
        stored_info,
        Enum.reduce(Catenary.timeline_logs(), [], fn n, a -> a ++ QuaggaDef.logs_for_name(n) end)
      )

    Catenary.dets_open(:timelines)

    case :dets.lookup(:timelines, :prev_hash) do
      [{:prev_hash, ^hash}] ->
        :ok

      _ ->
        index(logs, clump_id, :timelines)
        :dets.insert(:timelines, {:prev_hash, hash})
    end

    Catenary.dets_close(:timelines)
  end

  defp pick_logs(logs, matches) do
    set = Enum.filter(logs, fn {_, l, _} -> l in matches end)
    {set |> :erlang.term_to_binary() |> Blake2.hash2b(), set}
  end

  defp index([], _, which) do
    Phoenix.PubSub.local_broadcast(
      Catenary.PubSub,
      "background",
      {:completed, {:indexing, which, self()}}
    )

    :ok
  end

  defp index([{a, l, _} | rest], clump_id, which) do
    entries_index(Baobab.full_log(a, log_id: l, clump_id: clump_id), clump_id, which)
    index(rest, clump_id, which)
  end

  # This could maybe give up on a CBOR failure, eventurally
  # Right now we have a lot of mixed types
  defp entries_index([], _, _), do: :ok

  defp entries_index([entry | rest], clump_id, :timelines) do
    try do
      %Baobab.Entry{author: a, log_id: l, seqnum: s, payload: payload} = entry
      ident = Baobab.Identity.as_base62(a)
      {:ok, data, ""} = CBOR.decode(payload)

      old =
        case :dets.lookup(:timelines, ident) do
          [] -> []
          [{^ident, val}] -> val
        end

      insert = [{published(data), {ident, l, s}} | old] |> Enum.sort() |> Enum.uniq()

      :dets.insert(:timelines, {ident, insert})
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
        case :dets.lookup(:tags, e) do
          [] -> []
          [{^e, val}] -> val
        end

      into = (old ++ tags) |> Enum.sort() |> Enum.uniq()
      :dets.insert(:tags, {e, into})

      # Entries for tag
      for tag <- tags do
        old_val =
          case :dets.lookup(:tags, tag) do
            [] -> []
            [{^tag, val}] -> val
          end

        insert = [{published(data), e} | old_val] |> Enum.sort() |> Enum.uniq()
        :dets.insert(:tags, {tag, insert})
      end
    rescue
      _ -> :ok
    end

    entries_index(rest, clump_id, :tags)
  end

  defp entries_index([entry | rest], clump_id, :reactions) do
    try do
      %Baobab.Entry{payload: payload} = entry
      {:ok, data, ""} = CBOR.decode(payload)
      reacts = data["reactions"] |> Enum.map(fn s -> {"", s} end)
      [ent] = data["references"]
      e = List.to_tuple(ent)

      old =
        case :dets.lookup(:reactions, e) do
          [] -> []
          [{^e, val}] -> val
        end

      # This might eventually have log-scale counting
      into = (old ++ reacts) |> Enum.sort() |> Enum.uniq()
      :dets.insert(:reactions, {e, into})
    rescue
      _ -> :ok
    end

    entries_index(rest, clump_id, :reactions)
  end

  defp entries_index([entry | rest], clump_id, :aliases) do
    try do
      %Baobab.Entry{payload: payload} = entry
      {:ok, data, ""} = CBOR.decode(payload)
      :dets.insert(:aliases, {data["whom"], data["alias"]})
    rescue
      _ ->
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
          case :dets.lookup(:references, tref) do
            [] -> []
            [{^tref, val}] -> val
          end

        new_val = (old_val ++ [{published(data), index}]) |> Enum.sort() |> Enum.uniq()

        :dets.insert(:references, {tref, new_val})
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
