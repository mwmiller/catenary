defmodule Catenary.IndexWorker.Aliases do
  @name_atom :aliases
  use Catenary.IndexWorker.Common, name_atom: :aliases, indica: {"§", "~"}

  @moduledoc """
  Alias Indices
  """

  def update_from_logs(inform \\ []) do
    {identity, clump_id} = {Preferences.get(:identity), Preferences.get(:clump_id)}

    logs =
      :alias
      |> QuaggaDef.logs_for_name()

    clump_id
    |> Baobab.stored_info()
    |> Enum.reduce([], fn {a, l, _}, acc ->
      case a == identity and l in logs do
        true -> [{a, l} | acc]
        false -> acc
      end
    end)
    |> build_index(clump_id)

    run_complete(inform, self())
  end

  defp build_index([], _), do: :ok

  defp build_index([{a, l} | rest], clump_id) do
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
