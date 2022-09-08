defmodule Catenary.Indices do
  require Logger

  @moduledoc """
  Functions to recompute indices

  There is no sense in having stateful gen_servers
  for these.  We have no idea what to do if we fail.
  """

  defp dets_file(name) do
    Path.join([
      Application.get_env(:catenary, :application_dir, "~/.catenary"),
      name
    ])
    |> Path.expand()
    |> to_charlist
  end

  def index_references(stored_info) do
    :dets.open_file(:refs, file: dets_file("references.dets"), ram_file: true, auto_save: 1000)
    index(stored_info, Catenary.Quagga.log_ids_for_encoding(:cbor), :refs)
    :dets.close(:refs)
  end

  def index_aliases(id) do
    :dets.open_file(:aliases, file: dets_file("aliases.dets"), ram_file: true, auto_save: 1000)
    index([{id, 53, 1}], Catenary.Quagga.log_ids_for_encoding(:cbor), :aliases)
    :dets.close(:aliases)
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
