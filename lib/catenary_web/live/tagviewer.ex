defmodule Catenary.Live.TagViewer do
  require Logger
  use Phoenix.LiveComponent

  @impl true
  def update(%{entry: tag} = assigns, socket) do
    {:ok, assign(socket, Map.merge(assigns, %{card: extract(tag), tag: tag}))}
  end

  @impl true
  def render(%{card: :none} = assigns), do: Catenary.GeneriCard.no_data_card(assigns)

  def render(%{card: :error} = assigns), do: Catenary.GeneriCard.error_card(assigns)

  def render(assigns) do
    ~L"""
     <div id="tagview-wrap" class="col-span-2 overflow-y-auto max-h-screen m-2 p-x-2">
      <div class="min-w-full font-sans row-span-full">
        <h1 class="text=center">Entries tagged with "<%= @tag %>"</h1>
        <hr/>
        <%= for {type, entries} <- @card do %>
          <h3  class="pt-5 text-slate-600 dark:text-slate-300"><%= type %></h3>
        <div class="grid grid-cols-3 my-2">
        <%= entries %>
      </div>
    <% end %>
      <div class="mt-10 text-center"><button phx-click="tag-explorer">⧟ ### ⧟</button>
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
    do: prettify(rest, [{Catenary.pretty_log_name(k), title_entries(v)} | acc])

  defp title_entries(entries) do
    entries
    |> Enum.reduce("", fn {_d, t, {a, _, _} = e}, acc ->
      {:safe, ava} = Catenary.scaled_avatar(a, 1, ["m-1", "float-left", "align-middle"])

      acc <>
        "<div>" <> ava <> Catenary.view_entry_button(e, t) <> "</div>"
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
