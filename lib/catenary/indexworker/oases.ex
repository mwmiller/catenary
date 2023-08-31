defmodule Catenary.IndexWorker.Oases do
  @name_atom :oases
  use Catenary.IndexWorker.Common, name_atom: :oases, indica: {"⇆", "⇄"}

  @moduledoc """
  Oasis Indices
  """

  @display_count 4

  def update_from_logs(inform \\ []) do
    clump_id = Preferences.get(:clump_id)
    logs = QuaggaDef.logs_for_name(:oasis)

    clump_id
    |> Baobab.stored_info()
    |> Enum.reduce([], fn {a, l, e}, acc ->
      case l in logs do
        false -> acc
        true -> [{a, l, e} | acc]
      end
    end)
    |> extract_recents(clump_id, [])
    |> build_index(@display_count, clump_id)

    run_complete(inform, self())
  end

  defp build_index(all, count, clump_id) do
    recents =
      all
      |> Enum.sort_by(fn m -> Map.get(m, "running") end, :desc)
      |> Enum.uniq_by(fn %{"host" => h, "port" => p} -> {h, p} end)
      |> Enum.take(count)

    :ets.insert(@name_atom, {clump_id, recents})
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
