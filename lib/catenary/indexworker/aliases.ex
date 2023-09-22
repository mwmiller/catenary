defmodule Catenary.IndexWorker.Aliases do
  @name_atom :aliases
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
    |> build_index(clump_id)
  end

  defp build_index([], _), do: :ok

  defp build_index([{a, l, _} | rest], clump_id) do
    entries_index(Baobab.full_log(a, log_id: l, clump_id: clump_id), clump_id)
    build_index(rest, clump_id)
  end

  # This could maybe give up on a CBOR failure, eventually
  # Right now we have a lot of mixed types
  defp entries_index([], _), do: :ok

  defp entries_index([entry | rest], clump_id) do
    try do
      %Baobab.Entry{payload: payload} = entry
      {:ok, data, ""} = CBOR.decode(payload)
      :ets.match_delete(@name_atom, {:_, data["alias"]})
      :ets.insert(@name_atom, {data["whom"], data["alias"]})
    rescue
      _ ->
        :ok
    end

    entries_index(rest, clump_id)
  end
end
