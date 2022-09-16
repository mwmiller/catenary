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
        <div class="grid grid-cols-5 mt-10">
        <%= @card["entries"] %>
      </div>
      <div class="mt-10 text-center"><button phx-click="tag-explorer">⧟ ### ⧟</button>
      </div>
    """
  end

  defp extract(tag, icons) do
    %{"entries" => from_dets(tag, :tags) |> icon_entries(icons)}
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

  defp icon_entries([{a, _, _} = entry | rest], icons, acc) do
    icon_entries(
      rest,
      icons,
      acc <>
        "<div><button value=\"" <>
        Catenary.index_to_string(entry) <>
        "\" phx-click=\"view-entry\"><img src=\"" <>
        Catenary.identicon(a, icons, 4) <> "\"></button></div>"
    )
  end
end
