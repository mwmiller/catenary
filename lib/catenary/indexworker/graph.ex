defmodule Catenary.IndexWorker.Graph do
  @name_atom :graph

  use Catenary.IndexWorker.Common,
    name_atom: @name_atom,
    indica: {"⊛", "⛒"},
    logs: QuaggaDef.logs_for_name(@name_atom)

  alias Catenary.IndexWorker.Images
  require Logger

  @moduledoc """
  Functions to maintain the social graph
  """

  def do_index(todo, clump_id, prev_seen) do
    alias Catenary.BlockLog

    # One-time conversion: promote full-set literal blocks to patterns
    BlockLog.convert_literals(clump_id)

    identity = Preferences.get(:identity)
    total = length(todo)

    {t0, filtered} =
      :timer.tc(fn ->
        Enum.filter(todo, fn {a, _, _} -> a == identity end)
      end)

    {t1, ordered} =
      :timer.tc(fn ->
        order_operations(filtered, clump_id, [])
      end)

    {t2, reduced} =
      :timer.tc(fn ->
        reduce_operations(ordered)
      end)

    {t3, _} =
      :timer.tc(fn ->
        apply_operations(reduced, clump_id)
      end)

    Logger.debug(fn ->
      "[graph] do_index #{total} entries: " <>
        "filter=#{div(t0, 1000)}ms " <>
        "order=#{div(t1, 1000)}ms " <>
        "reduce=#{div(t2, 1000)}ms " <>
        "apply=#{div(t3, 1000)}ms " <>
        "total=#{div(t0 + t1 + t2 + t3, 1000)}ms"
    end)

    prev_seen
  end

  defp order_operations([], _, acc), do: acc |> Enum.reverse() |> Enum.sort()

  defp order_operations([{who, log_id, _} | rest], clump_id, acc) do
    order_operations(
      rest,
      clump_id,
      process_entries(Baobab.full_log(who, log_id: log_id, clump_id: clump_id), []) ++ acc
    )
  end

  defp process_entries([], acc), do: acc

  defp process_entries([curr | rest], acc) do
    %Baobab.Entry{payload: payload} = curr
    {:ok, data, ""} = CBOR.decode(payload)
    process_entries(rest, [{data["published"], data} | acc])
  rescue
    e ->
      Logger.warning("graph entry decode error: #{Exception.message(e)}")
      process_entries(rest, acc)
  end

  defp reduce_operations(list), do: reduce_operations(list, %{})
  defp reduce_operations([], acc), do: acc |> Map.to_list()

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
         [{_t, %{"action" => "logs", "accept" => al, "reject" => rl} = data} | rest],
         acc
       ) do
    am = MapSet.new(al)
    rm = MapSet.new(rl)
    bf = MapSet.new(Map.get(data, "block_families", []))
    uf = MapSet.new(Map.get(data, "unblock_families", []))

    um =
      acc
      |> Map.update("accept", am, fn ms -> MapSet.difference(MapSet.union(ms, am), rm) end)
      |> Map.update("reject", rm, fn ms -> MapSet.difference(MapSet.union(ms, rm), am) end)
      |> Map.update("block_families", bf, fn ms ->
        MapSet.union(ms, bf) |> MapSet.difference(uf)
      end)
      |> Map.update("unblock_families", uf, fn ms ->
        MapSet.union(ms, uf) |> MapSet.difference(bf)
      end)

    reduce_operations(rest, um)
  end

  defp reduce_operations([_undefined | rest], acc), do: reduce_operations(rest, acc)

  defp apply_operations([], _), do: :ok

  defp apply_operations([{"block", blockees} | rest], clump_id) do
    Enum.each(blockees, &Baobab.ClumpMeta.block(&1, clump_id))
    apply_operations(rest, clump_id)
  end

  defp apply_operations([{"unblock", backees} | rest], clump_id) do
    Enum.each(backees, &Baobab.ClumpMeta.unblock(&1, clump_id))
    apply_operations(rest, clump_id)
  end

  # "accept" is really just "not rejected" — skip it, the reject
  # operation below handles the full state.
  defp apply_operations([{"accept", _} | rest], clump_id) do
    apply_operations(rest, clump_id)
  end

  defp apply_operations([{"reject", bads} | rest], clump_id) do
    alias Catenary.BlockLog

    all_types = QuaggaDef.log_defs() |> Map.values() |> Enum.map(& &1.name)
    bad_atoms = Enum.map(bads, &String.to_existing_atom/1)
    rejected = MapSet.new(bad_atoms)
    accepted = MapSet.difference(MapSet.new(all_types), rejected)

    # Block rejected types, unblock accepted types — all by pattern
    Enum.each(bad_atoms, &BlockLog.block_name(&1, clump_id))
    Enum.each(accepted, &BlockLog.unblock_name(&1, clump_id))

    # Clean up image cache for blocked image log types
    image_names = Catenary.image_logs()
    blocked_images = Enum.filter(bad_atoms, fn name -> name in image_names end)

    if not Enum.empty?(blocked_images) do
      image_log_ids =
        blocked_images
        |> Enum.flat_map(&QuaggaDef.logs_for_name/1)
        |> MapSet.new()

      Images.purge_log_ids(image_log_ids, clump_id)
    end

    apply_operations(rest, clump_id)
  end

  defp apply_operations([{"block_families", fams} | rest], clump_id) do
    alias Catenary.BlockLog

    blocked =
      for {fam_name, tag} <- QuaggaDef.families(),
          Atom.to_string(fam_name) in fams do
        BlockLog.block_family(tag, clump_id)
      end

    _ = blocked
    apply_operations(rest, clump_id)
  end

  defp apply_operations([{"unblock_families", fams} | rest], clump_id) do
    alias Catenary.BlockLog

    unblocked =
      for {fam_name, tag} <- QuaggaDef.families(),
          Atom.to_string(fam_name) in fams do
        BlockLog.unblock_family(tag, clump_id)
      end

    _ = unblocked
    apply_operations(rest, clump_id)
  end

  defp apply_operations([_unknown | rest], clump_id) do
    apply_operations(rest, clump_id)
  end
end
