defmodule Catenary.Live.TagViewer do
  @moduledoc """
  LiveComponent rendering a single tag entry card.
  """
  use Phoenix.LiveComponent
  alias Catenary.Display

  @impl true
  def update(%{entry: tag} = assigns, socket) do
    {:ok, assign(socket, Map.merge(assigns, %{card: extract(tag), tag: tag}))}
  end

  @impl true
  def render(%{card: :none} = assigns), do: Catenary.GeneriCard.no_data_card(assigns)

  def render(%{card: :error} = assigns), do: Catenary.GeneriCard.error_card(assigns)

  def render(assigns) do
    ~H"""
    <div id="tagview-wrap" class="content-wrap">
      <div class="min-w-full row-span-full">
        <div class="flex items-center gap-2 mb-4">
          <span class="text-2xl text-amber-600 dark:text-amber-400">#</span>
          <h1 class="text-xl font-semibold text-slate-800 dark:text-slate-100">{@tag}</h1>
        </div>
        <div class="border-t border-slate-200 dark:border-slate-700 mb-4"></div>
        <%= for {type, entries} <- @card do %>
          <h3 class="text-xs font-semibold uppercase tracking-wide text-slate-400 dark:text-slate-500 mb-2">{type}</h3>
          <div class="grid grid-cols-3 gap-2 mb-4">
            {entries}
          </div>
        <% end %>
        <div class="mt-6 text-center">
          <button
            phx-click="tag-explorer"
            class="px-4 py-2 rounded-full border border-slate-200 dark:border-slate-700 text-sm text-slate-600 dark:text-slate-400 hover:border-amber-500 dark:hover:border-amber-400 hover:text-amber-600 dark:hover:text-amber-400 transition-colors"
          ><span>⧟</span></button>
        </div>
      </div>
    </div>
    """
  end

  defp extract(tag) do
    tag
    |> from_ets(:tags)
    |> Enum.group_by(fn {_, _, {_, l, _}} -> QuaggaDef.base_log(l) end)
    |> Map.to_list()
    |> prettify([])
    |> Enum.sort(:asc)
  end

  defp prettify([], acc), do: acc

  defp prettify([{k, v} | rest], acc),
    do: prettify(rest, [{Display.pretty_log_name(k), title_entries(v)} | acc])

  defp title_entries(entries) do
    clump_id = Catenary.Preferences.get(:clump_id)

    entries
    |> Enum.reduce("", fn {_d, t, e}, acc ->
      {a, l, _} = e
      entry_str = Catenary.index_to_string(e)
      {:safe, ava} = Display.scaled_avatar(a, 2, ["flex-none"])

      is_image =
        case l |> QuaggaDef.base_log() |> QuaggaDef.log_def() do
          %{type: <<"image/", _::binary>>} -> true
          _ -> false
        end

      content =
        if is_image do
          src = Catenary.image_src_for_entry(e, clump_id)
          ~s(<img class="w-16 h-16 object-cover rounded" src=") <> src <> ~s(">)
        else
          ~s(<span class="text-sm text-slate-700 dark:text-slate-300">) <> t <> ~s(</span>)
        end

      acc <>
        ~s(<button value="#{entry_str}" phx-click="view-entry" class="block w-full text-left rounded-lg border border-slate-200 dark:border-slate-700 p-2 hover:border-amber-500 dark:hover:border-amber-400 transition-colors flex items-center gap-2">) <>
        ava <> content <>
        ~s(</button>)
    end)
    |> Phoenix.HTML.raw()
  end

  defp from_ets(entry, table) do
    case :ets.lookup(table, {"", entry}) do
      [] -> []
      [{_, v}] -> v
    end
  end
end
