defmodule Catenary.Navigation do
  alias Catenary.{Timeline, Authorline, Tagline}

  @moduledoc """
  Functions to move between entries along different lines
  """

  @doc """
  Move to a different entry based on the supplied entry and Phoenix assigns
  """
  def move_to(
        motion,
        from,
        %{
          store: store,
          entry: entry,
          identity: id,
          entry_back: entry_back,
          view: view,
          entry_fore: entry_fore
        } = assigns
      ) do
    sent =
      case from do
        :current -> %{view: view, entry: entry}
        supplied -> supplied
      end

    case motion do
      "back" ->
        case entry_back do
          [] ->
            sent

          [prev | rest] ->
            Map.merge(prev, %{entry_back: rest, entry_fore: [sent | entry_fore]})
        end

      "forward" ->
        case entry_fore do
          [] ->
            sent

          [next | rest] ->
            Map.merge(next, %{entry_fore: rest, entry_back: [sent | entry_back]})
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

  defp new_path(
         next,
         %{view: view, entry: entry, store: store, entry_back: back},
         check_existence? \\ true
       ) do
    at = %{view: view, entry: entry}
    to = if check_existence?, do: maybe_wrap(next, store), else: next

    case to == at do
      true -> to
      false -> Map.merge(to, %{entry_back: [at | back], entry_fore: []})
    end
  end

  defp maybe_wrap(%{view: view, entry: {a, l, e}}, store) do
    max =
      store
      |> Enum.reduce(1, fn
        {^a, ^l, s}, _acc -> s
        _, acc -> acc
      end)

    entry =
      cond do
        # Wrap around
        e < 1 -> {a, l, max}
        e > max -> {a, l, 1}
        true -> {a, l, e}
      end

    %{view: view, entry: entry}
  end

  defp maybe_wrap(entry, _), do: entry
end
