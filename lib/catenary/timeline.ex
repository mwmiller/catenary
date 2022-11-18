defmodule Catenary.Timeline do
  @moduledoc """
  Identity timeline functions

  Also handles items which are not in the timeline index by
  moving incrementally along the same log.
  """

  # Compile-time computed so it can be used in the guard clause
  @timeline_ids Enum.reduce(Catenary.timeline_logs(), [], fn l, a ->
                  a ++ QuaggaDef.logs_for_name(l)
                end)

  @doc """
  Select the next timeline entry from a given entry
  """
  def next(entry), do: move(entry, :next)

  @doc """
  Select the previous entry from a given entry
  """
  def prev(entry), do: move(entry, :prev)

  defp move(%{view: :entries, entry: {:tag, _t}} = c, _), do: c
  defp move(%{view: :entries, entry: {:profile, _a}} = c, _), do: c

  defp move(%{view: :entries, entry: {a, l, e} = entry}, dir) when l in @timeline_ids do
    Catenary.dets_open(:timelines)

    timeline =
      case :dets.lookup(:timelines, a) do
        [] -> [{<<>>, {a, l, e}}]
        [{^a, tl}] -> tl
      end

    Catenary.dets_close(:timelines)

    wherearewe =
      case Enum.find_index(timeline, fn {_, listed} -> listed == entry end) do
        nil -> 0
        n -> n
      end

    {_t, to_entry} =
      case dir do
        :prev -> Enum.at(timeline, wherearewe - 1)
        :next -> Enum.at(timeline, wherearewe + 1, Enum.at(timeline, 0))
      end

    %{view: :entries, entry: to_entry}
  end

  defp move(%{view: :entries, entry: {a, l, e}}, :prev),
    do: %{view: :entries, entry: {a, l, e - 1}}

  defp move(%{view: :entries, entry: {a, l, e}}, :next),
    do: %{view: :entries, entry: {a, l, e + 1}}

  defp move(curr, _), do: curr
end
