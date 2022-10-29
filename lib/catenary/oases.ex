defmodule Catenary.Oases do
  @moduledoc """
  Functions for dealing with Oasis logs
  """
  @oasis_log_ids QuaggaDef.logs_for_name(:oasis)

  @doc """
  Produce a list of recently announced Oases found in
  the provided store for the provided clump_id
  """
  def recents(store, clump_id, count) do
    store
    |> Enum.filter(fn {_, l, _} -> l in @oasis_log_ids end)
    |> extract_recents(clump_id, DateTime.now!("Etc/UTC"), [])
    |> Enum.take(count)
  end

  defp extract_recents([], _, _, acc) do
    # Put them in age order
    # Pick the most recent for any host/port dupes
    # Display a max of 3
    acc
    |> Enum.sort_by(fn m -> Map.get(m, "running") end, :desc)
    |> Enum.uniq_by(fn %{"host" => h, "port" => p} -> {h, p} end)
  end

  defp extract_recents([{a, l, e} | rest], clump_id, now, acc) do
    try do
      %Baobab.Entry{payload: payload} = Baobab.log_entry(a, e, log_id: l, clump_id: clump_id)
      {:ok, map, ""} = CBOR.decode(payload)

      case map do
        %{"running" => ts} ->
          then = ts |> Timex.parse!("{ISO:Extended}")

          cond do
            Timex.diff(then, now, :hour) > -337 ->
              extract_recents(rest, clump_id, now, [
                Map.merge(map, %{:id => {a, l, e}, "running" => then}) | acc
              ])

            true ->
              extract_recents(rest, clump_id, now, acc)
          end

        _ ->
          extract_recents(rest, clump_id, now, acc)
      end
    rescue
      _ -> extract_recents(rest, clump_id, now, acc)
    end
  end
end
