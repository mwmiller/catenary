defmodule Catenary.IndexWorker.Tags do
  @name_atom :tags
  use Catenary.IndexWorker.Common, name_atom: :tags, indica: {"|", "#"}

  @moduledoc """
  Tag Indices
  """

  def update_from_logs(inform \\ []) do
    clump_id = Preferences.get(:clump_id)

    logs =
      :tag
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

  defp build_index([], _) do
    # This is a bit redundant during conversion
    :ets.match(:tags, :"$1")
    |> Enum.reduce([], fn [{f, i} | _], a ->
      case f do
        {"", t} ->
          [
            {t, Enum.any?(i, fn {_t, e} -> not Catenary.Preferences.shown?(e) end), length(i)}
            | a
          ]

        _ ->
          a
      end
    end)
    |> group_sizes
    |> then(fn items -> :ets.insert(@name_atom, {:display, items}) end)
  end

  defp build_index([{a, l} | rest], clump_id) do
    entries_index(Enum.reverse(Baobab.full_log(a, log_id: l, clump_id: clump_id)), clump_id)
    build_index(rest, clump_id)
  end

  def group_sizes(items) do
    items
    |> Enum.group_by(fn {_, _, c} -> trunc(:math.log(c)) end)
    |> Map.to_list()
    |> Enum.sort(:desc)
    |> Enum.reduce([], fn {_s, i}, acc -> [Enum.shuffle(i) | acc] end)
    |> Enum.reverse()
  end

  # This could maybe give up on a CBOR failure, eventually
  # Right now we have a lot of mixed types
  defp entries_index([], _), do: :ok

  defp entries_index([entry | rest], clump_id) do
    # This is a two-way index
    try do
      %Baobab.Entry{payload: payload} = entry
      {:ok, data, ""} = CBOR.decode(payload)
      tags = data["tags"] |> Enum.map(fn s -> {"", String.trim(s)} end)
      [ent] = data["references"]
      e = List.to_tuple(ent)
      # Tags for entry
      old =
        case :ets.lookup(@name_atom, e) do
          [] -> []
          [{^e, val}] -> val
        end

      into = (old ++ tags) |> Enum.sort() |> Enum.uniq()
      :ets.insert(@name_atom, {e, into})

      # Entries for tag
      for tag <- tags do
        old_val =
          case :ets.lookup(@name_atom, tag) do
            [] -> []
            [{^tag, val}] -> val
          end

        insert =
          [{Indices.published_date(data), e} | old_val]
          |> Enum.sort()
          |> Enum.uniq_by(fn {_p, e} -> e end)

        :ets.insert(@name_atom, {tag, insert})
      end
    rescue
      _ -> :ok
    end

    entries_index(rest, clump_id)
  end
end
