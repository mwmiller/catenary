defmodule Catenary.IndexWorker.Aliases do
  use Catenary.IndexWorker.Common,
    name_atom: :aliases,
    indica: {"§", "~"},
    logs: QuaggaDef.logs_for_name(:alias)

  require Logger

  @moduledoc """
  Alias Indices
  """

  def do_index(_todo, clump_id, prev_seen) do
    # Always process ALL alias entries — not just the incremental todo —
    # so the latest entry for each whom-key replaces any previous one.
    # Aliases are small enough that a full pass is cheap.
    keepers = Baobab.Identity.list() |> Enum.map(fn {_n, k} -> k end)

    result =
      Baobab.stored_info(clump_id)
      |> Enum.filter(fn {a, l, _} -> a in keepers and l in @logs_of_interest end)
      |> build_index(clump_id, [])
      |> Map.new()

    Catenary.State.set_aliases(result)
    prev_seen
  end

  defp build_index([], _, acc), do: acc

  defp build_index([{a, l, _} | rest], clump_id, acc) do
    build_index(
      rest,
      clump_id,
      entries_index(Baobab.full_log(a, log_id: l, clump_id: clump_id), clump_id, acc)
    )
  end

  # Each entry is {whom, alias_name}.  Because entries are processed in
  # chronological order, the latest assignment of a name wins: if "Quagga"
  # is reassigned from key A to key B, key A loses the name.

  defp entries_index([], _, acc), do: acc

  defp entries_index([entry | rest], clump_id, acc) do
    na =
      try do
        %Baobab.Entry{payload: payload} = entry
        {:ok, data, ""} = CBOR.decode(payload)
        whom = data["whom"]
        name = data["alias"]

        # Find and remove any previous owner of this name
        prev_owner =
          Enum.find_value(acc, fn
            {k, ^name} -> k
            _ -> nil
          end)

        acc = if prev_owner, do: List.keydelete(acc, prev_owner, 0), else: acc
        List.keystore(acc, whom, 0, {whom, name})
      rescue
        e ->
          Logger.warning("alias decode error: #{inspect(e, limit: 50, printable_limit: 200)}")
          acc
      end

    entries_index(rest, clump_id, na)
  end
end
