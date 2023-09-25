defmodule Catenary.IndexWorker.Tags do
  @name_atom :tags
  use Catenary.IndexWorker.Common,
    name_atom: :tags,
    indica: {"|", "#"},
    logs: QuaggaDef.logs_for_name(:tag)

  @moduledoc """
  Tag Indices
  """

  def do_index(todo, clump_id) do
    todo
    |> build_index(clump_id)
  end

  defp build_index([], _) do
    # This is a bit redundant during conversion
    :ets.match(:tags, :"$1")
    |> Enum.reduce([], fn [{f, i} | _], a ->
      case f do
        {"", t} -> [{t, length(i)} | a]
        _ -> a
      end
    end)
    |> group_sizes
    |> then(fn items -> :ets.insert(@name_atom, {:display, items}) end)
  end

  defp build_index([{a, l, _} | rest], clump_id) do
    entries_index(Enum.reverse(Baobab.full_log(a, log_id: l, clump_id: clump_id)), clump_id)
    build_index(rest, clump_id)
  end

  def group_sizes(items) do
    items
    |> Enum.group_by(fn {_, c} -> trunc(:math.log(c)) end)
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
      e = {oa, ol, oe} = List.to_tuple(ent)
      # Now try to get a title from the original
      %Baobab.Entry{payload: pl} = Baobab.log_entry(oa, oe, log_id: ol, clump_id: clump_id)
      {:ok, od, ""} = CBOR.decode(pl)

      title =
        case od["title"] do
          <<>> -> Catenary.added_title("empty")
          nil -> Catenary.added_title("none")
          t -> t
        end

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
          [{Indices.published_date(data), title, e} | old_val]
          |> Enum.sort()
          |> Enum.uniq_by(fn {_p, _t, e} -> e end)

        :ets.insert(@name_atom, {tag, insert})
      end
    rescue
      _ -> :ok
    end

    entries_index(rest, clump_id)
  end
end
