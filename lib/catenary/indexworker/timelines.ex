defmodule Catenary.IndexWorker.Timelines do
  @name_atom :timelines
  use Catenary.IndexWorker.Common,
    name_atom: :timelines,
    indica: {"✐", "✎"},
    logs:
      Enum.reduce(Catenary.timeline_logs(), [], fn n, a -> a ++ QuaggaDef.logs_for_name(n) end)

  @moduledoc """
  Timeline Indices
  """

  def do_index(todo, clump_id) do
    todo |> build_index(clump_id)
  end

  defp build_index([], _), do: :ok

  defp build_index([{a, l, _} | rest], clump_id) do
    entries_index(Enum.reverse(Baobab.full_log(a, log_id: l, clump_id: clump_id)), clump_id)
    build_index(rest, clump_id)
  end

  # This could maybe give up on a CBOR failure, eventually
  # Right now we have a lot of mixed types
  defp entries_index([], _), do: :ok

  defp entries_index([entry | rest], clump_id) do
    try do
      %Baobab.Entry{author: a, log_id: l, seqnum: s, payload: payload} = entry
      ident = Baobab.Identity.as_base62(a)
      {:ok, data, ""} = CBOR.decode(payload)

      old =
        case :ets.lookup(@name_atom, ident) do
          [] -> []
          [{^ident, val}] -> val
        end

      insert = [{Indices.published_date(data), {ident, l, s}} | old] |> Enum.sort() |> Enum.uniq()

      :ets.insert(@name_atom, {ident, insert})
    rescue
      _ -> :ok
    end

    entries_index(rest, clump_id)
  end
end
