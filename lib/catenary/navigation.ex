defmodule Catenary.Navigation do
  alias Catenary.{Timeline, Authorline, Tagline}

  @moduledoc """
  Functions to move between entries along different lines
  """

  @doc """
  Move to a different entry based on the supplied entry and Phoenix assigns
  """
  def move_to(motion, from, assigns) do
    sent = sent_state(from, assigns)
    transition(motion, from, sent, assigns)
  end

  # The current location we are navigating away from. When moving from the
  # LiveView's current location, carry over the back/forward history so the
  # returned state always carries `entry_back` and `entry_fore`.
  defp sent_state(:current, %{view: view, entry: entry, entry_back: back, entry_fore: fore}) do
    %{view: view, entry: entry, entry_back: back, entry_fore: fore}
  end

  defp sent_state(supplied, _assigns), do: supplied

  # Back/forward pop directly from the history stacks and bypass `new_path`.
  defp transition("back", sent, _from, %{entry_back: entry_back, entry_fore: entry_fore}) do
    case entry_back do
      [] -> sent
      [prev | rest] -> Map.merge(prev, %{entry_back: rest, entry_fore: [sent | entry_fore]})
    end
  end

  defp transition("forward", sent, _from, %{entry_back: entry_back, entry_fore: entry_fore}) do
    case entry_fore do
      [] -> sent
      [next | rest] -> Map.merge(next, %{entry_fore: rest, entry_back: [sent | entry_back]})
    end
  end

  defp transition(motion, from, sent, %{identity: id, store: store} = assigns) do
    {next, check?} = resolve_next(motion, sent, store, id)
    new_path(next, from, sent, assigns, check?)
  end

  # Resolves the target "next" state for motions that flow through `new_path`.
  # `{"new"` intentionally skips existence checking (it does not appear in the
  # store yet); every other motion resolves to a next state and is then run
  # through `new_path` with existence checking.
  defp resolve_next("specified", sent, _store, _id), do: {sent, true}
  defp resolve_next("new", sent, _store, _id), do: {sent, false}
  defp resolve_next("prev-entry", sent, _store, _id), do: {Timeline.prev(sent), true}
  defp resolve_next("next-entry", sent, _store, _id), do: {Timeline.next(sent), true}
  defp resolve_next("next-author", sent, store, _id), do: {Authorline.next(sent, store), true}
  defp resolve_next("prev-author", sent, store, _id), do: {Authorline.prev(sent, store), true}

  defp resolve_next("origin", _sent, _store, id) do
    Phoenix.PubSub.local_broadcast(Catenary.PubSub, "ui", "toggle-profile")
    {%{view: :entries, entry: {:profile, id}}, true}
  end

  defp resolve_next(<<"prev-tag-", tag::binary>>, sent, _store, _id) do
    {Tagline.prev(sent, tag), true}
  end

  defp resolve_next(<<"next-tag-", tag::binary>>, sent, _store, _id) do
    {Tagline.next(sent, tag), true}
  end

  defp resolve_next(_motion, sent, _store, _id), do: {sent, true}

  # `at` is the LiveView's current location (the origin we navigate away from),
  # preserved with its own back/forward history. Navigating `:current` to the
  # same current entry is a no-op (no history is recorded); a supplied
  # `from` argument is treated as the new destination and always records the
  # current location onto the back stack.
  defp new_path(
         next,
         from,
         _sent,
         %{view: view, entry: entry, entry_back: back, entry_fore: fore, store: store},
         check_existence?
       ) do
    at = %{view: view, entry: entry, entry_back: back, entry_fore: fore}
    to = if check_existence?, do: maybe_wrap(next, store), else: next

    if stays_put?(from, at, to) do
      at
    else
      Map.merge(to, %{entry_back: [at | at.entry_back], entry_fore: []})
    end
  end

  defp stays_put?(:current, %{view: view, entry: entry}, %{view: to_view, entry: to_entry}),
    do: view == to_view and entry == to_entry

  defp stays_put?(_from, _at, _to), do: false

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
