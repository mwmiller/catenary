defmodule Catenary.Live.TagExplorer do
  @moduledoc """
  LiveComponent rendering an explorer of tag entries.
  """
  use Phoenix.LiveComponent

  @impl true
  def update(%{entry: which} = assigns, socket) do
    {:ok,
     assign(socket, Map.merge(assigns, %{card: extract(which), sort: :alpha, filter: ""}))}
  end

  @impl true
  def render(%{card: :none} = assigns), do: Catenary.GeneriCard.no_data_card(assigns)

  def render(%{card: :error} = assigns), do: Catenary.GeneriCard.error_card(assigns)

  def render(assigns) do
    ~H"""
    <div id="tag-explore-wrap" class="content-wrap">
      <div class="flex flex-col gap-2">
        <h1 class="text-lg font-semibold text-slate-800 dark:text-slate-100">Tag Explorer</h1>
        <p :if={@card["tags"] == []} class="text-sm text-slate-400 dark:text-slate-500">
          No tag messages.
        </p>
        <div :if={@card["tags"] != []} class="flex items-center gap-3">
          <input
            type="text"
            placeholder="Filter tags..."
            value={@filter}
            phx-keyup="tag-filter"
            phx-target={@myself}
            name="filter"
            class="w-48 rounded-full border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800 px-3 py-1 text-sm text-slate-900 dark:text-slate-100 placeholder:text-slate-400 dark:placeholder:text-slate-500"
          />
          <div class="flex rounded-full border border-slate-300 dark:border-slate-600 overflow-hidden text-xs">
            <button
              phx-click="tag-sort"
              phx-value-sort="alpha"
              phx-target={@myself}
              class={"px-3 py-1 transition-colors #{if @sort == :alpha, do: "bg-amber-500 text-white", else: "text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-700"}"}
            >↕</button>
            <button
              phx-click="tag-sort"
              phx-value-sort="popular"
              phx-target={@myself}
              class={"px-3 py-1 transition-colors #{if @sort == :popular, do: "bg-amber-500 text-white", else: "text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-700"}"}
            >◆</button>
          </div>
        </div>
        <div :if={@card["tags"] != []} class="flex flex-row flex-wrap gap-1.5">
          {render_tags(@card["tags"], @sort, @filter)}
        </div>
      </div>
    </div>
    """
  end

  defp render_tags(all_groups, sort, filter) do
    tags =
      all_groups
      |> List.flatten()
      |> then(fn tags ->
        case sort do
          :alpha -> Enum.sort_by(tags, fn {t, _} -> t end)
          :popular -> Enum.sort_by(tags, fn {_, c} -> -c end)
        end
      end)
      |> then(fn tags ->
        if filter == "" do
          tags
        else
          Enum.filter(tags, fn {t, _} ->
            String.contains?(String.downcase(t), String.downcase(filter))
          end)
        end
      end)

    thresholds = percentile_thresholds(tags)

    tags
    |> Enum.map(fn {t, c} ->
      {size_class, bg_class, text_class, count_class} = tier(c, thresholds)
      ~s(<button value="#{t}" phx-click="view-tag"><div class="rounded-full border #{bg_class} px-2.5 py-0.5 transition-colors hover:border-amber-500 dark:hover:border-amber-400"><span class="#{text_class} #{size_class}">#{t}</span><span class="ml-1 #{count_class}">#{c}</span></div></button>)
    end)
    |> then(fn
      [] -> ~s(<span class="text-sm text-slate-400 dark:text-slate-500">No matching tags.</span>)
      tags -> Enum.join(tags)
    end)
    |> Phoenix.HTML.raw()
  end

  defp percentile_thresholds(tags) do
    counts = tags |> Enum.map(fn {_, c} -> c end) |> Enum.sort()
    n = length(counts)
    p99 = percentile(counts, 0.99, n)
    p90 = percentile(counts, 0.90, n)
    p70 = percentile(counts, 0.70, n)
    {p99, p90, p70}
  end

  defp percentile(sorted, p, n) do
    rank = Float.ceil(p * (n - 1)) |> trunc()
    Enum.at(sorted, rank, 0)
  end

  defp tier(count, {p99, p90, p70}) do
    cond do
      count >= p99 ->
        {"text-base font-bold", "border-amber-500/60 bg-amber-50 dark:bg-amber-900/30",
         "text-amber-900 dark:text-amber-100", "text-amber-600 dark:text-amber-400"}

      count >= p90 ->
        {"text-sm font-semibold", "border-amber-400/40 bg-amber-50/50 dark:bg-amber-900/15",
         "text-amber-800 dark:text-amber-200", "text-amber-600 dark:text-amber-400"}

      count >= p70 ->
        {"text-xs font-medium", "border-slate-200 dark:border-slate-700",
         "text-amber-700 dark:text-amber-300", "text-slate-400 dark:text-slate-500"}

      true ->
        {"text-xs", "border-slate-200 dark:border-slate-700",
         "text-slate-500 dark:text-slate-400", "text-slate-400 dark:text-slate-500"}
    end
  end

  @impl true
  def handle_event("tag-sort", %{"sort" => sort}, socket) do
    {:noreply, assign(socket, :sort, String.to_existing_atom(sort))}
  end

  def handle_event("tag-filter", %{"value" => filter}, socket) do
    {:noreply, assign(socket, :filter, filter)}
  end

  def handle_event("view-tag" = event, payload, socket) do
    send(socket.parent_pid, {__MODULE__, event, payload})
    {:noreply, socket}
  end

  defp extract(:all) do
    :ets.lookup(:tags, :display)
    |> then(fn
      [{_, items}] -> items
      _ -> []
    end)
    |> then(fn tags -> %{"tags" => tags} end)
  end

  defp extract(_), do: :none
end
