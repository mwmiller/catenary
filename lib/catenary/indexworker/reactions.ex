defmodule Catenary.IndexWorker.Reactions do
  @name_atom :reactions
  use Catenary.IndexWorker.Common, name_atom: :reactions, indica: {"※", "⌘"}

  @moduledoc """
  Tag Indices
  """

  def update_from_logs(inform \\ []) do
    clump_id = Preferences.get(:clump_id)

    logs =
      :react
      |> QuaggaDef.logs_for_name()

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
    entries_index(Enum.reverse(Baobab.full_log(a, log_id: l, clump_id: clump_id)), clump_id)
    build_index(rest, clump_id)
  end

  # This could maybe give up on a CBOR failure, eventually
  # Right now we have a lot of mixed types
  defp entries_index([], _), do: :ok

  defp entries_index([entry | rest], clump_id) do
    try do
      %Baobab.Entry{payload: payload} = entry
      {:ok, data, ""} = CBOR.decode(payload)
      reacts = data["reactions"] |> Enum.map(fn s -> {"", s} end)
      [ent] = data["references"]
      e = List.to_tuple(ent)

      old =
        case :ets.lookup(@name_atom, e) do
          [] -> []
          [{^e, val}] -> val
        end

      # This might eventually have log-scale counting
      into = (old ++ reacts) |> Enum.sort() |> Enum.uniq()
      :ets.insert(@name_atom, {e, into})
    rescue
      _ -> :ok
    end

    entries_index(rest, clump_id)
  end
end