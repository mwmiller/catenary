defmodule Catenary.ProfileMerge do
  require Logger

  @moduledoc """
  Combine log entries into a unified profile view
  """

  def update_from_logs(clump_id, inform \\ nil) do
    logs = QuaggaDef.logs_for_name(:about)

    ppid = self()

    Task.start(fn ->
      clump_id
      |> Baobab.stored_info()
      |> Enum.reduce([], fn {a, l, _}, acc ->
        case l in logs do
          false -> acc
          true -> [{a, l} | acc]
        end
      end)
      |> gather_updates(clump_id, %{})
      |> Map.to_list()
      |> build_index(clump_id)

      case inform do
        nil -> :ok
        pid -> Process.send(pid, {:completed, {:indexing, :about, ppid}}, [])
      end
    end)
  end

  defp gather_updates([], _, acc), do: acc

  defp gather_updates([{who, log_id} | rest], clump_id, acc) do
    gather_updates(
      rest,
      clump_id,
      acc
      |> Map.put_new(who, [])
      |> Map.update!(who, fn extant ->
        extant ++ process_entries(Baobab.full_log(who, log_id: log_id, clump_id: clump_id), [])
      end)
    )
  end

  defp process_entries([], acc), do: acc

  defp process_entries([curr | rest], acc) do
    try do
      %Baobab.Entry{payload: payload} = curr
      {:ok, data, ""} = CBOR.decode(payload)
      process_entries(rest, [{data["published"], data} | acc])
    rescue
      _ -> process_entries(rest, acc)
    end
  end

  defp build_index([], _cid), do: :ok

  defp build_index([{ident, updates} | rest], clump_id) do
    final_form =
      updates
      |> Enum.sort()
      |> Enum.reduce(%{}, fn {_when, what}, acc -> Map.merge(acc, what) end)

    case final_form do
      %{"avatar" => [a, l, e]} ->
        :ets.insert(:avatars, {ident, {a, l, e, clump_id}})

      _ ->
        :ok
    end

    :ets.insert(:about, {ident, final_form})
    build_index(rest, clump_id)
  end
end
