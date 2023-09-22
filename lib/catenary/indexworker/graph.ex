defmodule Catenary.IndexWorker.Graph do
  @name_atom :graph

  use Catenary.IndexWorker.Common,
    name_atom: @name_atom,
    indica: {"⊛", "⛒"},
    logs: QuaggaDef.logs_for_name(@name_atom)

  @moduledoc """
  Functions to maintain the social graph
  """

  # We only apply the requested identity on the requested clump
  # It is assumed that identities sharing this application
  # share a view on how it ought to be sanitised.  However, it
  # is possible that someone is doing a per-clump identity.
  # The easiest way to determine this is to only
  # apply combinations which we actually see requested.

  # Facets complicate this further.  We're forced to assume
  # synchronised clocks between all facet providers.
  # Our best hope is that there are not conflicts in
  # the timing error bars.

  def do_index(todo, clump_id) do
    identity = Preferences.get(:identity)

    todo
    |> Enum.filter(fn {a, _, _} -> a == identity end)
    |> order_operations(clump_id, [])
    |> reduce_operations()
    |> note_operations()
    |> apply_operations(clump_id)
  end

  defp order_operations([], _, acc), do: acc |> Enum.sort()

  defp order_operations([{who, log_id, _} | rest], clump_id, acc) do
    order_operations(
      rest,
      clump_id,
      acc ++ process_entries(Baobab.full_log(who, log_id: log_id, clump_id: clump_id), [])
    )
  end

  # This exists because we don't want to lose everything after a single bad entry somehow
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

  defp note_operations(ops, acc \\ [])
  defp note_operations([], acc), do: Enum.reverse(acc)
  # We only care about certain operations in certain ways
  defp note_operations([{"reject", rejects} = op | rest], acc) do
    Catenary.Preferences.reject_log_name_set(
      rejects
      |> Enum.map(fn s -> String.to_atom(s) end)
    )

    note_operations(rest, [op | acc])
  end

  defp note_operations([op | rest], acc), do: note_operations(rest, [op | acc])

  # It might be confusing if we take in an empty map accumulator
  # and return a list of tuples, so this convenience function
  defp reduce_operations(list), do: reduce_operations(list, %{})
  defp reduce_operations([], acc), do: acc |> Map.to_list()
  # We shouldn't ever need these times after sorting, but I 
  # have maintained it for now in case I am proved wrong
  defp reduce_operations([{_t, %{"action" => "block", "whom" => whom}} | rest], acc) do
    um =
      acc
      |> Map.update("block", MapSet.new([whom]), fn ms -> MapSet.put(ms, whom) end)
      |> Map.update("unblock", MapSet.new(), fn ms -> MapSet.delete(ms, whom) end)

    reduce_operations(rest, um)
  end

  defp reduce_operations([{_t, %{"action" => "unblock", "whom" => whom}} | rest], acc) do
    um =
      acc
      |> Map.update("unblock", MapSet.new([whom]), fn ms -> MapSet.put(ms, whom) end)
      |> Map.update("block", MapSet.new(), fn ms -> MapSet.delete(ms, whom) end)

    reduce_operations(rest, um)
  end

  defp reduce_operations(
         [{_t, %{"action" => "logs", "accept" => al, "reject" => rl}} | rest],
         acc
       ) do
    am = MapSet.new(al)
    rm = MapSet.new(rl)

    um =
      acc
      |> Map.update("accept", am, fn ms -> MapSet.difference(MapSet.union(ms, am), rm) end)
      |> Map.update("reject", rm, fn ms -> MapSet.difference(MapSet.union(ms, rm), am) end)

    reduce_operations(rest, um)
  end

  defp reduce_operations([_undefined | rest], acc), do: reduce_operations(rest, acc)

  # As of this point, the order doesn't matter.
  # Canceling operations have been combined from their original (partial?) ordering.
  # Per usual, I don't have good error handling to start
  # Clearly not idempotent, but not changing state should have no side-effects.
  defp apply_operations([], _), do: :ok

  defp apply_operations([{"block", blockees} | rest], clump_id) do
    blockees
    |> Enum.map(fn a -> Baobab.ClumpMeta.block(a, clump_id) end)

    apply_operations(rest, clump_id)
  end

  defp apply_operations([{"unblock", backees} | rest], clump_id) do
    backees |> Enum.map(fn a -> Baobab.ClumpMeta.unblock(a, clump_id) end)
    apply_operations(rest, clump_id)
  end

  defp apply_operations([{"accept", oks} | rest], clump_id) do
    oks
    |> Enum.reduce([], fn n, a -> a ++ QuaggaDef.logs_for_name(String.to_atom(n)) end)
    |> Enum.sort()
    |> Enum.map(fn l -> Baobab.ClumpMeta.unblock(l, clump_id) end)

    apply_operations(rest, clump_id)
  end

  defp apply_operations([{"reject", bads} | rest], clump_id) do
    bads
    |> Enum.reduce([], fn n, a -> a ++ QuaggaDef.logs_for_name(String.to_atom(n)) end)
    |> Enum.sort()
    |> Enum.map(fn l -> Baobab.ClumpMeta.block(l, clump_id) end)

    apply_operations(rest, clump_id)
  end

  # No catch-all function head. The filler should have managed things.  If we let
  # operations we're supposed to apply pass this far we should blow up
  # when they don't match.
end
