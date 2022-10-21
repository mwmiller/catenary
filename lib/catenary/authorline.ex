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

  defp move({:tag, t}, _, _), do: {:tag, t}

  defp move(entry, store, dir) do
    store
    |> possibles(entry, dir)
    |> dropper(entry, dir)
    |> select(entry)
  end

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
