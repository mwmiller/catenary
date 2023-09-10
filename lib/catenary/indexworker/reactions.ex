defmodule Catenary.IndexWorker.Reactions do
  @name_atom :reactions
  use Catenary.IndexWorker.Common,
    name_atom: :reactions,
    indica: {"※", "⌘"},
    logs: QuaggaDef.logs_for_name(:react)

  @moduledoc """
  Tag Indices
  """

  def do_index(todo, clump_id) do
    todo
    |> build_index(clump_id)
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
