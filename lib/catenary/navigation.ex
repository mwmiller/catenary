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

    entry =
      case motion do
        "specified" ->
          sent

        "prev-entry" ->
          Timeline.prev(sent)

        "next-entry" ->
          Timeline.next(sent)

        "next-author" ->
          Authorline.next(sent, store)

        "prev-author" ->
          Authorline.prev(sent, store)

        "origin" ->
          {:profile, id}

        _ ->
          sent
      end

    %{view: :entries, entry: maybe_wrap(entry, store)}
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
