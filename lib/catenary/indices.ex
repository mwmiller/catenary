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
    index([{id, 53, 1}], Catenary.Quagga.log_ids_for_encoding(:cbor), :aliases)
    Catenary.dets_close(:aliases)
  end

  defp index([], _, _), do: :ok

  defp index([{a, l, _} | rest], cbors, which) do
    # Side-effects everywhere!
    case l in cbors do
      true -> entries_index(Baobab.full_log(a, log_id: l), which)
      false -> :ok
    end

    index(rest, cbors, which)
  end

  # This could maybe give up on a CBOR failure, eventurally
  # Right now we have a lot of mixed types
  defp entries_index([], _), do: :ok

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
