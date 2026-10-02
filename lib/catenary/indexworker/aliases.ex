defmodule Catenary.IndexWorker.Aliases do
  use Catenary.IndexWorker.Common,
    name_atom: :aliases,
    indica: {"§", "~"},
    logs: QuaggaDef.logs_for_name(:alias)

  @moduledoc """
  Alias Indices

  Aliases are local to the identity that wrote them. Every identity keeps
  its own alias log, so this index folds the active identity's log and no
  other: a name some other local identity set never becomes a candidate
  here, and switching identities folds the new log rather than carrying the
  previous one over.
  """

  def do_index(_todo, clump_id, prev_seen) do
    # The whole log every time, not just the incremental todo: a name can
    # move between keys within one pass, and every claim has to be in the
    # map before the winner of a name is known.
    me = Preferences.get(:identity)

    result =
      Baobab.stored_info(clump_id)
      |> Enum.filter(fn {author, log_id, _} -> author == me and log_id in @logs_of_interest end)
      |> Enum.flat_map(fn {author, log_id, _} -> claims(author, log_id, clump_id) end)
      |> build()

    Catenary.State.set_aliases(result)
    prev_seen
  end

  @doc """
  Build the `{key, name}` map from decoded alias payloads, in any order.

  A name belongs to one key, so the newest claim for it wins and the key
  that held it drops it. Claims are ordered by their `published` time rather
  than by the order the store returned them, which makes the fold the same
  map whatever order the log comes back in. A claim with no readable time
  sorts ahead of every dated one, so leaving a time off can never take a
  name from a claim that carries one. A claim that does not name a key and
  a name in text is skipped rather than allowed to write either half of a
  mapping.
  """
  @spec build([map()]) :: %{binary() => binary()}
  def build(payloads) when is_list(payloads) do
    payloads
    |> Enum.filter(&is_map/1)
    |> Enum.sort_by(&claim_key/1)
    |> Enum.reduce(%{}, &claim/2)
  end

  defp claims(author, log_id, clump_id) do
    author
    |> Baobab.full_log(log_id: log_id, clump_id: clump_id)
    |> Enum.flat_map(&decode/1)
  end

  defp decode(%Baobab.Entry{payload: payload}) do
    case CBOR.decode(payload) do
      {:ok, data, ""} when is_map(data) -> [data]
      _ -> []
    end
  rescue
    _ -> []
  end

  # Oldest first, so the reduce leaves the newest claim for a name standing.
  defp claim_key(data), do: {published(data), Map.get(data, "whom"), Map.get(data, "alias")}

  defp published(%{"published" => t} = data) when is_binary(t) do
    case Indices.published_date(data) do
      ts when is_integer(ts) -> ts
      _ -> 0
    end
  end

  defp published(_data), do: 0

  defp claim(%{"whom" => whom, "alias" => name}, acc)
       when is_binary(whom) and whom != "" and is_binary(name) and name != "" do
    acc
    |> release(name)
    |> Map.put(whom, name)
  end

  defp claim(_data, acc), do: acc

  # A name belongs to exactly one key, so handing it over takes it away from
  # whichever key was holding it.
  defp release(acc, name) do
    case Enum.find(acc, fn {_key, held} -> held == name end) do
      {previous, _} -> Map.delete(acc, previous)
      nil -> acc
    end
  end
end
