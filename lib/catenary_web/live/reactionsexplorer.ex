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
      <div class="flex flex-col gap-3">
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
            ><span title="Most recent reactions">↻</span></button>
            <button
              phx-click="react-sort"
              phx-value-sort="popular"
              phx-target={@myself}
              class={"px-3 py-1 transition-colors #{if @sort == :popular, do: "bg-amber-500 text-white", else: "text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-700"}"}
            ><span title="Most reacted to">♥</span></button>
          </div>
        </div>
        <div :if={@card != []} class="flex flex-col gap-1.5">
          {render_reactions(@card, @sort, @clump_id)}
        </div>
      </div>
    </div>
    """
  end

  defp render_reactions(entries, sort, clump_id) do
    entries
    |> sort_entries(sort)
    |> Enum.map(fn {entry, reactions} ->
      for_display(entry, reactions, clump_id)
    end)
    |> then(fn
      [] -> ~s(<span class="text-sm text-slate-400 dark:text-slate-500">No reactions yet.</span>)
      items -> Enum.join(items)
    end)
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
      ~s(<div class="rounded-lg border border-slate-200 dark:border-slate-700 p-2 hover:border-amber-500 dark:hover:border-amber-400 transition-colors flex items-center gap-3 w-full text-left">) <>
      ~s(<span class="text-lg shrink-0">#{emojis}</span>) <>
      ~s(<span class="text-sm text-slate-700 dark:text-slate-300 truncate flex-1">#{title}</span>) <>
      ~s(<span class="text-xs text-slate-400 dark:text-slate-500 shrink-0">#{count}x</span>) <>
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
