defmodule Catenary.IndexWorker.Timelines do
  @name_atom :timelines
  use Catenary.IndexWorker.Common, name_atom: :timelines, indica: {"⫝̸", "⫝"}

  @moduledoc """
  Timeline Indices
  """

  def update_from_logs(inform \\ []) do
    clump_id = Preferences.get(:clump_id)

    logs =
      Enum.reduce(Catenary.timeline_logs(), [], fn n, a -> a ++ QuaggaDef.logs_for_name(n) end)

    clump_id
    |> Baobab.stored_info()
    |> Enum.reduce([], fn {a, l, _}, acc ->
      case l in logs do
        true -> [{a, l} | acc]
        false -> acc
      end
    end)
    |> build_index(clump_id)

    run_complete(inform, self())
  end

  defp build_index([], _), do: :ok

  defp build_index([{a, l} | rest], clump_id) do
    entries_index(Baobab.full_log(a, log_id: l, clump_id: clump_id), clump_id)
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
