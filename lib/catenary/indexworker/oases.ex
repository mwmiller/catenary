defmodule Catenary.IndexWorker.Oases do
  use Catenary.IndexWorker.Common,
    name_atom: :oases,
    indica: {"⇆", "⇄"},
    logs: QuaggaDef.logs_for_name(:oasis)

  @moduledoc """
  Oasis Indices
  """

  @display_count 4

  def do_index(_todo, clump_id) do
    # Rebuild from the full store rather than just the incremental diff.
    # The index worker's initial :continue load can race Baobab's async
    # :status load, so a diff against the cold store would index nothing
    # and never refresh (Indices.update/0 only re-casts on a hash change).
    clump_id
    |> Baobab.stored_info()
    |> Enum.filter(fn {_a, l, _e} -> l in @logs_of_interest end)
    |> extract_recents(clump_id, [])
    |> build_index(@display_count)
    |> Catenary.State.update_oases()
  end

  defp build_index(all, count) do
    all
    |> Enum.sort_by(fn m -> Map.get(m, "running") end, :desc)
    |> Enum.uniq_by(fn %{"host" => h, "port" => p} -> {h, p} end)
    |> Enum.take(count)
  end

  defp extract_recents([], _, acc), do: acc

  defp extract_recents([{a, l, e} | rest], clump_id, acc) do
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
