defmodule Catenary.Authorline do
  @moduledoc """
  Authorline functions

  Enables moving between entry authors seamlessly
  """

  @doc """
  Find an entry for the next author following a given entry
  from the provided store
  """
  def next(entry, store), do: move(entry, store, :next)

  @doc """
  Find an entry for the previous author preceding a given entry
  from the provided store
  """
  def prev(entry, store), do: move(entry, store, :prev)

  defp move(%{view: entries, entry: {:tag, _t}} = c, _, _), do: c

  defp move(%{view: :entries, entry: entry}, store, dir) do
    dest =
      store
      |> possibles(entry, dir)
      |> dropper(entry, dir)
      |> select(entry)

    %{view: :entries, entry: dest}
  end

  defmodule Catenary.Tagline do
    @moduledoc """
    Tag navigation functions
    """

    @doc """
    Select the next tagine entry from a given entry
    """
    def next(entry, tag), do: move(entry, tag, :next)

    @doc """
    Select the previous entry from a given entry
    """
    def prev(entry, tag), do: move(entry, tag, :prev)

    defp move({a, l, e} = entry, tag, dir) do
      Catenary.dets_open(:tags)
      ti = {"", tag}

      tagline =
        case :dets.lookup(:tags, {"", tag}) do
          [] -> [{0, {a, l, e}}]
          [{^ti, tl}] -> tl
        end

      Catenary.dets_close(:tags)

      wherearewe =
        case Enum.find_index(tagline, fn {_, listed} -> listed == entry end) do
          nil -> 0
          n -> n
        end

      {_t, to_entry} =
        case dir do
          :prev -> Enum.at(tagline, wherearewe - 1)
          :next -> Enum.at(tagline, wherearewe + 1, Enum.at(tagline, 0))
        end

      to_entry
    end

    defp move(entry, _, _), do: entry
  end

  defp move(curr, _, _), do: curr

  defp possibles(store, entry, dir) do
    sdir =
      case dir do
        :next -> :desc
        :prev -> :asc
      end

    case entry do
      {:profile, _} -> store
      {_, log_id, _} -> Enum.filter(store, fn {_, l, _} -> log_id == l end)
    end
    |> Enum.sort(sdir)
  end

  defp dropper(possibles, entry, dir) do
    author =
      case entry do
        {:profile, a} -> a
        {a, _, _} -> a
      end

    val =
      case dir do
        :next -> Enum.drop_while(possibles, fn {a, _, _} -> a >= author end)
        :prev -> Enum.drop_while(possibles, fn {a, _, _} -> a <= author end)
      end

    case val do
      [] -> List.first(possibles)
      [next | _] -> next
    end
  end

  defp select({a, _, _}, {:profile, _}), do: {:profile, a}
  defp select({a, l, _}, {_, _, s}), do: {a, l, s}
end
