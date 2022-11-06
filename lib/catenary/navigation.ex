defmodule Catenary.Navigation do
  alias Catenary.{Timeline, Authorline, Tagline}

  @moduledoc """
  Functions to move between entries along different lines
  """

  @doc """
  Move to a different entry based on the supplied entry and Phoenix assigns
  """
  def move_to(motion, from, %{:store => store, :identity => id} = assigns) do
    sent =
      case from do
        :current -> assigns.entry
        supplied -> supplied
      end

    case motion do
      "back" ->
        case assigns.entry_back do
          [] ->
            base_val(sent)

          [prev | rest] ->
            Map.merge(
              base_val(prev),
              %{
                entry_back: rest,
                entry_fore: [sent | assigns.entry_fore]
              }
            )
        end

      "forward" ->
        case assigns.entry_fore do
          [] ->
            base_val(sent)

          [next | rest] ->
            Map.merge(
              base_val(next),
              %{
                entry_fore: rest,
                entry_back: [sent | assigns.entry_back]
              }
            )
        end

      # This does not yet appear in the store
      # We assume we got it right
      "new" ->
        new_path(sent, assigns, false)

      "specified" ->
        new_path(sent, assigns)

      "prev-entry" ->
        sent |> Timeline.prev() |> new_path(assigns)

      "next-entry" ->
        sent |> Timeline.next() |> new_path(assigns)

      "next-author" ->
        sent |> Authorline.next(store) |> new_path(assigns)

      "prev-author" ->
        sent |> Authorline.prev(store) |> new_path(assigns)

      <<"prev-tag-", tag::binary>> ->
        sent |> Tagline.prev(tag) |> new_path(assigns)

      <<"next-tag-", tag::binary>> ->
        sent |> Tagline.next(tag) |> new_path(assigns)

      "origin" ->
        new_path({:profile, id}, assigns)

      _ ->
        new_path(sent, assigns)
    end
  end

  defp base_val(to), do: %{view: :entries, entry: to}

  defp new_path(next, %{entry: at, store: store, entry_back: back}, check_existence? \\ true) do
    to = if check_existence?, do: maybe_wrap(next, store), else: next

    case to == at do
      true -> base_val(to)
      false -> Map.merge(base_val(to), %{entry_back: [at | back], entry_fore: []})
    end
  end

  defp maybe_wrap({a, l, e}, store) do
    max =
      store
      |> Enum.reduce(1, fn
        {^a, ^l, s}, _acc -> s
        _, acc -> acc
      end)

    cond do
      # Wrap around
      e < 1 -> {a, l, max}
      e > max -> {a, l, 1}
      true -> {a, l, e}
    end
  end

  defp maybe_wrap(entry, _), do: entry
end
