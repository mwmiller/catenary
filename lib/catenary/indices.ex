defmodule Catenary.Indices do
  require Logger

  @moduledoc """
  Functions to recompute indices

  There is no sense in having stateful gen_servers
  for these.  We have no idea what to do if we fail.
  """

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
      tags = data["tags"]
      [ent] = data["references"]
      e = List.to_tuple(ent)
      # Tags for entry
      case :dets.lookup(:tags, e) do
        [] -> :dets.insert(:tags, {e, tags})
        [{^e, val}] -> :dets.insert(:tags, {e, Enum.uniq(val ++ tags)})
      end

      # Entries for tag
      for tag <- tags do
        case :dets.lookup(:tags, tag) do
          [] -> :dets.insert(:tags, {tag, [e]})
          [{^tag, val}] -> :dets.insert(:tags, {tag, Enum.uniq(val ++ [e])})
        end
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
      :dets.insert(:aliases, {data["whom"], data["alias"]})
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

        case :dets.lookup(:refs, tref) do
          [] -> :dets.insert(:refs, {tref, [index]})
          [{^tref, val}] -> :dets.insert(:refs, {tref, Enum.uniq(val ++ [index])})
        end
      end
    rescue
      _ ->
        :ok
    end

    entries_index(rest, :refs)
  end
end
