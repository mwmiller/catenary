defmodule Catenary.IndexWorker.Mentions do
  @name_atom :mentions
  use Catenary.IndexWorker.Common,
    name_atom: :mentions,
    indica: {"∏", "∑"},
    logs: QuaggaDef.logs_for_name(:mention)

  @moduledoc """
  Mention Indices
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
    # This is a two-way index
    try do
      %Baobab.Entry{payload: payload} = entry
      {:ok, data, ""} = CBOR.decode(payload)
      mentions = data["mentions"] |> Enum.map(fn s -> {"", String.trim(s)} end)
      [ent] = data["references"]
      e = List.to_tuple(ent)
      # Mentions for entry
      old =
        case :ets.lookup(@name_atom, e) do
          [] -> []
          [{^e, val}] -> val
        end

      into = (old ++ mentions) |> Enum.sort() |> Enum.uniq()
      :ets.insert(@name_atom, {e, into})

      # Entries for mentioned
      for mention <- mentions do
        old_val =
          case :ets.lookup(@name_atom, mention) do
            [] -> []
            [{^mention, val}] -> val
          end

        insert =
          [{Indices.published_date(data), e} | old_val]
          |> Enum.sort()
          |> Enum.uniq_by(fn {_p, e} -> e end)

        :ets.insert(@name_atom, {mention, insert})
      end
    rescue
      _ -> :ok
    end

    entries_index(rest, clump_id)
  end
end
