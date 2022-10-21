defmodule Catenary.Navigation do
  alias Catenary.{Timeline, Authorline}

  @moduledoc """
  Functions to move between entries along different lines
  """

  @doc """
  Move to a different entry based on the the current entry,
  provided store and controling identity

  """
  def move_to(motion, current, store, id) do
    entry =
      case motion do
        "specified" ->
          current

        "prev-entry" ->
          Timeline.prev(current)

        "next-entry" ->
          Timeline.next(current)

        "next-author" ->
          Authorline.next(current, store)

        "prev-author" ->
          Authorline.prev(current, store)

        "origin" ->
          {:profile, id}

        _ ->
          current
      end

    # This is a bit ugly with only the one
    # non-index entry, but maybe it will prove useful later.
    where =
      case entry do
        {a, l, e} ->
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

        _ ->
          entry
      end

    %{view: :entries, entry: where}
  end
end
