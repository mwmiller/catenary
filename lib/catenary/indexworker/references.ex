defmodule Catenary.IndexWorker.References do
  @name_atom :references
  use Catenary.IndexWorker.Common,
    name_atom: :references,
    indica: {"↪︎", "↩︎"},
    logs: QuaggaDef.logs_for_encoding(:cbor)

  @moduledoc """
  Reference Indices
  """

  def do_index(todo, clump_id) do
    todo
    |> build_index(clump_id)
  end

  defp build_index([], _), do: :ok

  defp build_index([{a, l, _} | rest], clump_id) do
    entries_index(Enum.reverse(Baobab.full_log(a, log_id: l, clump_id: clump_id)), clump_id)
    build_index(rest, clump_id)
  end

  # This could maybe give up on a CBOR failure, eventually
  # Right now we have a lot of mixed types
  defp entries_index([], _), do: :ok

  defp entries_index([entry | rest], clump_id) do
    try do
      %Baobab.Entry{author: a, log_id: l, seqnum: s, payload: payload} = entry
      index = {Baobab.Identity.as_base62(a), l, s}
      {:ok, data, ""} = CBOR.decode(payload)

      for lref <- Map.get(data, "references") do
        tref = lref |> List.to_tuple()

        old_val =
          case :ets.lookup(@name_atom, tref) do
            [] -> []
            [{^tref, val}] -> val
          end

        new_val =
          (old_val ++ [{Indices.published_date(data), index}]) |> Enum.sort() |> Enum.uniq()

        :ets.insert(@name_atom, {tref, new_val})
      end
    rescue
      _ ->
        :ok
    end

    entries_index(rest, clump_id)
  end
end
