defmodule Catenary.Navigation do
  alias Catenary.{Timeline, Authorline}

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
            non_stack_nav(sent, assigns)

          [prev | rest] ->
            %{
              view: :entries,
              entry: prev,
              entry_back: rest,
              entry_fore: [sent | assigns.entry_fore]
            }
        end

      "forward" ->
        case assigns.entry_fore do
          [] ->
            non_stack_nav(sent, assigns)

          [next | rest] ->
            %{
              view: :entries,
              entry: next,
              entry_fore: rest,
              entry_back: [sent | assigns.entry_back]
            }
        end

      "specified" ->
        non_stack_nav(sent, assigns)

      "prev-entry" ->
        sent |> Timeline.prev() |> non_stack_nav(assigns)

      "next-entry" ->
        sent |> Timeline.next() |> non_stack_nav(assigns)

      "next-author" ->
        sent |> Authorline.next(store) |> non_stack_nav(assigns)

      "prev-author" ->
        sent |> Authorline.prev(store) |> non_stack_nav(assigns)

      "origin" ->
        non_stack_nav({:profile, id}, assigns)

      _ ->
        non_stack_nav(sent, assigns)
    end
  end

  def non_stack_nav(next, %{entry: at, store: store, entry_back: back}) do
    to = maybe_wrap(next, store)

    case to == at do
      true -> %{view: :entries, entry: to}
      false -> %{view: :entries, entry: to, entry_back: [at | back]}
    end
  end

  def maybe_wrap({a, l, e}, store) do
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

  def maybe_wrap(entry, _), do: entry
end
