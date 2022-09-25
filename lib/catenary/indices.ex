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
    for table <- [:refs, :tags, :aliases] do
      Catenary.dets_open(table)
      :dets.delete_all_objects(table)
      Catenary.dets_close(table)
    end
  end

  def index_references(stored_info) do
    Catenary.dets_open(:refs)
    index(stored_info, Catenary.Quagga.log_ids_for_encoding(:cbor), :refs)
    Catenary.dets_close(:refs)
  end

  def index_aliases(id) do
    Catenary.dets_open(:aliases)
    :dets.delete_all_objects(:aliases)
    index([{id, 53, 1}], [53], :aliases)
    Catenary.dets_close(:aliases)
  end

  def index_tags(stored_info) do
    Catenary.dets_open(:tags)
    index(stored_info, [749], :tags)
    Catenary.dets_close(:tags)
  end

  defp index([], _, _), do: :ok

  defp index([{a, l, _} | rest], log_ids, which) do
    # Side-effects everywhere!
    case l in log_ids do
      true -> entries_index(Baobab.full_log(a, log_id: l), which)
      false -> :ok
    end

    index(rest, log_ids, which)
  end

  # This could maybe give up on a CBOR failure, eventurally
  # Right now we have a lot of mixed types
  defp entries_index([], _), do: :ok

  defp entries_index([entry | rest], :tags) do
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

    entries_index(rest, :tags)
  end

  defp entries_index([entry | rest], :aliases) do
    try do
      %Baobab.Entry{payload: payload} = entry
      {:ok, data, ""} = CBOR.decode(payload)
      :dets.insert(:aliases, {published(data), data["whom"], data["alias"]})
    rescue
      _ ->
        :ok
    end

    entries_index(rest, :aliases)
  end

  defp entries_index([entry | rest], :refs) do
    try do
      %Baobab.Entry{author: a, log_id: l, seqnum: s, payload: payload} = entry
      index = {Baobab.b62identity(a), l, s}
      {:ok, data, ""} = CBOR.decode(payload)

      for lref <- Map.get(data, "references") do
        tref = lref |> List.to_tuple()

        old_val =
          case :dets.lookup(:refs, tref) do
            [] -> []
            [{^tref, val}] -> val
          end

        new_val = (old_val ++ [{published(data), index}]) |> Enum.sort() |> Enum.uniq()
        :dets.insert(:refs, {tref, new_val})
      end
    rescue
      _ ->
        :ok
    end

    entries_index(rest, :refs)
  end

  defp published(data) when is_map(data) do
    case data["published"] do
      nil ->
        ""

      t ->
        t
        |> Timex.parse!("{ISO:Extended}")
        |> Timex.Timezone.convert(Timex.Timezone.local())
    end
  end

  defp published(_), do: ""
end
