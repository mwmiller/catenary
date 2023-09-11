defmodule Catenary.IndexWorker.Oases do
  @name_atom :oases
  use Catenary.IndexWorker.Common,
    name_atom: :oases,
    indica: {"⇆", "⇄"},
    logs: QuaggaDef.logs_for_name(:oasis)

  @moduledoc """
  Oasis Indices
  """

  @display_count 4

  def do_index(todo, clump_id) do
    todo
    |> extract_recents(clump_id, [])
    |> build_index(@display_count, clump_id)
  end

  defp build_index(all, count, clump_id) do
    recents =
      all
      |> Enum.sort_by(fn m -> Map.get(m, "running") end, :desc)
      |> Enum.uniq_by(fn %{"host" => h, "port" => p} -> {h, p} end)
      |> Enum.take(count)
      |> Enum.reduce(%{}, fn i, m -> Map.put(m, i["name"], i) end)

    prev =
      case :ets.lookup(@name_atom, clump_id) do
        [] -> %{}
        [{^clump_id, items}] -> items
      end

    # We let the list grow if a newly named oasis is discovered
    :ets.insert(@name_atom, {clump_id, Map.merge(prev, recents)})
  end

  defp extract_recents([], _, acc), do: acc

  defp extract_recents([{a, l, e} | rest], clump_id, acc) do
    try do
      %Baobab.Entry{payload: payload} =
        Baobab.log_entry(a, e, log_id: l, clump_id: clump_id)

      {:ok, map, ""} = CBOR.decode(payload)

      case map do
        %{"running" => _} ->
          extract_recents(rest, clump_id, [Map.merge(map, %{:id => {a, l, e}}) | acc])

        _ ->
          extract_recents(rest, clump_id, acc)
      end
    rescue
      _ -> extract_recents(rest, clump_id, acc)
    end
  end
end
