defmodule Catenary.Indices do
  require Logger

  @moduledoc """
  Functions to recompute indices

  There is no sense in having stateful gen_servers
  for these.  We have no idea what to do if we fail.
  """

  def index_references(stored_info) do
    filename =
      Path.join([
        Application.get_env(:catenary, :application_dir, "~/.catenary"),
        "references.dets"
      ])
      |> Path.expand
      |> to_charlist

    :dets.open_file(:refs, file: filename, ram_file: true, auto_save: 1000)
    index(stored_info, :refs)
    :dets.close(:refs)
  end

  defp index([], _), do: :ok

  defp index([{a, l, _} | rest], :refs) do
    entries_index(Baobab.full_log(a, log_id: l), :refs)
    index(rest, :refs)
  end

  # This could maybe give up on a CBOR failure, eventurally
  # Right now we have a lot of mixed types
  defp entries_index([], _), do: :ok

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
