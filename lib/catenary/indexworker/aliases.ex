defmodule Catenary.IndexWorker.Aliases do
  use Catenary.IndexWorker.Common,
    name_atom: :aliases,
    indica: {"§", "~"},
    logs: QuaggaDef.logs_for_name(:alias)

  @moduledoc """
  Alias Indices
  """

  def do_index(todo, clump_id) do
    # This should be always small enough that MapSet
    # would be overkill
    keepers = Baobab.Identity.list() |> Enum.map(fn {_n, k} -> k end)

    todo
    |> Enum.filter(fn {a, _, _} -> a in keepers end)
    |> build_index(clump_id, %{})
    |> Catenary.State.set_aliases()
  end

  defp build_index([], _, acc), do: acc

  defp build_index([{a, l, _} | rest], clump_id, acc) do
    build_index(
      rest,
      clump_id,
      entries_index(Baobab.full_log(a, log_id: l, clump_id: clump_id), clump_id, acc)
    )
  end

  # This could maybe give up on a CBOR failure, eventually
  # Right now we have a lot of mixed types
  defp entries_index([], _, acc), do: acc

  defp entries_index([entry | rest], clump_id, acc) do
    na =
      try do
        %Baobab.Entry{payload: payload} = entry
        {:ok, data, ""} = CBOR.decode(payload)
        Map.put(acc, data["whom"], data["alias"])
      rescue
        _ -> acc
      end

    entries_index(rest, clump_id, na)
  end
end
