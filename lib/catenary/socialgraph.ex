defmodule Catenary.SocialGraph do
  require Logger

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
  def update_from_logs(identity, clump_id) do
    :graph
    |> QuaggaDef.logs_for_name()
    |> order_operations(identity, clump_id, [])
    |> reduce_operations()
    |> apply_operations(clump_id)
  end

  defp order_operations([], _, _, acc), do: acc |> Enum.sort()

  defp order_operations([log_id | rest], who, clump_id, acc) do
    order_operations(
      rest,
      who,
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
      process_entries(rest, [{data["published"], data["whom"], data["action"]} | acc])
    rescue
      _ -> process_entries(rest, acc)
    end
  end

  # It might be confusing if we take in an empty map accumulator
  # and return a list of tuples, so this convenience function
  defp reduce_operations(list), do: reduce_operations(list, %{})
  defp reduce_operations([], acc), do: acc |> Map.to_list()
  # We shouldn't ever need these times after sorting, but I 
  # have maintained it for now in case I am proved wrong
  defp reduce_operations([{_t, who, "block"} | rest], acc) do
    um =
      acc
      |> Map.update("block", MapSet.new([who]), fn ms -> MapSet.put(ms, who) end)
      |> Map.update("unblock", MapSet.new(), fn ms -> MapSet.delete(ms, who) end)

    reduce_operations(rest, um)
  end

  defp reduce_operations([{_t, who, "unblock"} | rest], acc) do
    um =
      acc
      |> Map.update("unblock", MapSet.new([who]), fn ms -> MapSet.put(ms, who) end)
      |> Map.update("block", MapSet.new(), fn ms -> MapSet.delete(ms, who) end)

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
    |> Enum.map(fn a -> Baobab.ClumpMeta.block_author(a, clump_id) end)

    apply_operations(rest, clump_id)
  end

  defp apply_operations([{"unblock", backees} | rest], clump_id) do
    backees |> Enum.map(fn a -> Baobab.ClumpMeta.unblock_author(a, clump_id) end)
    apply_operations(rest, clump_id)
  end

  # No catch-all function head. The filler should have managed things.  If we let
  # operations we're supposed to apply pass this far we should blow up
  # when they don't match.
end
