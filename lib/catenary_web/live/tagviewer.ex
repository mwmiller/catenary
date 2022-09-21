defmodule Catenary.Live.TagViewer do
  require Logger
  use Phoenix.LiveComponent

  @impl true
  def update(%{tag: which} = assigns, socket) do
    {:ok, assign(socket, Map.merge(assigns, %{card: extract(which, assigns.iconset)}))}
  end

  @impl true
  def render(%{card: :none} = assigns) do
    ~L"""
      <div class="min-w-full font-sans row-span-full">
        <h1>No data just yet</h1>
      </div>
    """
  end

  def render(%{card: :error} = assigns) do
    ~L"""
      <div class="min-w-full font-sans row-span-full">
        <h1>Unrenderable card</h1>
      </div>
    """
  end

  def render(assigns) do
    ~L"""
      <div class="min-w-full font-sans row-span-full">
        <h1 class="text=center">Entries tagged with "<%= @tag %>"</h1>
        <hr/>
        <%= for {type, entries} <- @card do %>
          <h3  class="pt-5 text-slate-600 dark:text-slate-300"><%= type %></h3>
        <div class="grid grid-cols-5 my-2">
        <%= entries %>
      </div>
    <% end %>
      <div class="mt-10 text-center"><button phx-click="tag-explorer">⧟ ### ⧟</button>
      </div>
    """
  end

  defp extract(tag, icons) do
    tag
    |> from_dets(:tags)
    |> Enum.group_by(fn {_, l, _} -> l end)
    |> Enum.map(fn {k, v} ->
      {k
       |> Catenary.Quagga.log_def()
       |> Map.get(:name)
       |> Atom.to_string()
       |> String.capitalize(), icon_entries(v, icons)}
    end)
    |> Enum.sort(:asc)
  end

  defp from_dets(entry, table) do
    Catenary.dets_open(table)

    val =
      case :dets.lookup(table, entry) do
        [] -> []
        [{^entry, v}] -> v
      end

    Catenary.dets_close(table)
    val
  end

  defp icon_entries(list, icons, acc \\ "")
  defp icon_entries([], _icons, acc), do: Phoenix.HTML.raw(acc)

  defp icon_entries([{a, _, e} = entry | rest], icons, acc) do
    icon_entries(
      rest,
      icons,
      acc <>
        "<div><button value=\"" <>
        Catenary.index_to_string(entry) <>
        "\" phx-click=\"view-entry\"><img src=\"" <>
        Catenary.identicon(a, icons, 4) <>
        "\" title=\"" <> entry_title(entry) <> "\"\></button></div>"
    )
  end

  defp entry_title({a, _, e} = entry),
    do: "entry " <> Integer.to_string(e) <> " from " <> Catenary.short_id(a)
end
