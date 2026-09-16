defmodule Catenary.Live.ReactionsExplorer do
  @moduledoc """
  LiveComponent rendering an explorer of reacted entries.
  """
  use Phoenix.LiveComponent
  alias Catenary.Display

  @impl true
  def update(%{entry: which, clump_id: clump_id} = assigns, socket) do
    {:ok,
     assign(socket, Map.merge(assigns, %{card: extract(which, clump_id), sort: :recent}))}
  end

  @impl true
  def render(%{card: :none} = assigns), do: Catenary.GeneriCard.no_data_card(assigns)

  def render(%{card: :error} = assigns), do: Catenary.GeneriCard.error_card(assigns)

  def render(assigns) do
    ~H"""
    <div id="reactions-explore-wrap" class="content-wrap">
      <div class="flex flex-col gap-5">
        <h1 class="text-lg font-semibold text-slate-800 dark:text-slate-100">Reactions Explorer</h1>
        <p :if={@card == []} class="text-sm text-slate-400 dark:text-slate-500">
          No reaction messages.
        </p>
        <div :if={@card != []} class="flex items-center gap-3">
          <div class="flex rounded-full border border-slate-300 dark:border-slate-600 overflow-hidden text-xs">
            <button
              phx-click="react-sort"
              phx-value-sort="recent"
              phx-target={@myself}
              class={"px-3 py-1 transition-colors #{if @sort == :recent, do: "bg-amber-500 text-white", else: "text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-700"}"}
            ><span title="Most recent reactions">◷</span></button>
            <button
              phx-click="react-sort"
              phx-value-sort="popular"
              phx-target={@myself}
              class={"px-3 py-1 transition-colors #{if @sort == :popular, do: "bg-amber-500 text-white", else: "text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-700"}"}
            ><span title="Most reacted to">★</span></button>
          </div>
        </div>
        <div :if={@card != []}>
          {render_grouped(@card, @sort, @clump_id)}
        </div>
      </div>
    </div>
    """
  end

  defp render_grouped(entries, sort, clump_id) do
    entries
    |> Enum.flat_map(fn {entry, reactions} ->
      reactions
      |> Enum.uniq_by(fn {_, r} -> r end)
      |> Enum.map(fn {_, r} -> {r, entry, reactions} end)
    end)
    |> Enum.group_by(fn {emoji, _, _} -> emoji end)
    |> Enum.sort_by(fn {emoji, items} -> {-length(items), emoji} end)
    |> Enum.map(fn {emoji, items} ->
      sorted =
        items
        |> Enum.map(fn {_, entry, reactions} -> {entry, reactions} end)
        |> then(fn items -> sort_entries(items, sort) end)

      pills = Enum.map_join(sorted, fn {entry, reactions} -> for_display(entry, reactions, clump_id) end)

      ~s(<div class="flex flex-col gap-2">) <>
        ~s(<h3 class="text-xs font-semibold uppercase tracking-wide text-slate-400 dark:text-slate-500 flex items-center gap-1.5">) <>
        ~s(<span class="text-base">#{emoji}</span></h3>) <>
        ~s(<div class="flex flex-row flex-wrap gap-1.5">#{pills}</div>) <>
        ~s(</div>)
    end)
    |> Enum.join("")
    |> Phoenix.HTML.raw()
  end

  defp for_display({a, l, e} = entry, reactions, clump_id) do
    emojis = reactions |> Enum.map(fn {_, r} -> r end) |> Enum.uniq() |> Enum.join(" ")
    count = length(reactions)

    title =
      try do
        %Baobab.Entry{payload: payload} = Baobab.log_entry(a, e, log_id: l, clump_id: clump_id)
        {:ok, data, ""} = CBOR.decode(payload)
        Display.entry_title(l, data)
      rescue
        _ -> Catenary.index_to_string(entry)
      end

    entry_str = Catenary.index_to_string(entry)

    ~s(<button value="#{entry_str}" phx-click="view-entry">) <>
      ~s(<div class="rounded-full border border-slate-200 dark:border-slate-700 px-2.5 py-0.5 transition-colors hover:border-amber-500 dark:hover:border-amber-400 inline-flex items-center gap-1.5">) <>
      ~s(<span class="text-sm">#{emojis}</span>) <>
      ~s(<span class="text-sm text-slate-700 dark:text-slate-300">#{title}</span>) <>
      ~s(<span class="text-xs text-slate-400 dark:text-slate-500">#{count}</span>) <>
      ~s(</div></button>)
  end

  defp sort_entries(entries, :recent) do
    entries
    |> Enum.sort_by(fn {_, reactions} ->
      reactions |> List.last() |> elem(0)
    end, :desc)
  end

  defp sort_entries(entries, :popular) do
    entries
    |> Enum.sort_by(fn {_, reactions} -> -length(reactions) end)
  end

  @impl true
  def handle_event("react-sort", %{"sort" => sort}, socket) do
    {:noreply, assign(socket, :sort, String.to_existing_atom(sort))}
  end

  defp extract(:all, _clump_id) do
    :ets.tab2list(:reactions)
    |> Enum.filter(fn {_, reactions} -> reactions != [] end)
  end

  defp extract(_, _), do: :none
end
