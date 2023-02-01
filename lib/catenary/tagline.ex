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

  defp move(%{view: :entries, entry: {a, l, e} = entry}, tag, dir) do
    ti = {"", tag}

    tagline =
      case :ets.lookup(:tags, {"", tag}) do
        [] -> [{0, {a, l, e}}]
        [{^ti, tl}] -> tl
      end

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

    %{view: :entries, entry: to_entry}
  end

  defp move(entry, _, _), do: entry
end
