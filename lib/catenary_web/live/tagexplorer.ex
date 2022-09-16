defmodule Catenary.Live.TagExplorer do
  require Logger
  use Phoenix.LiveComponent

  @impl true
  def update(%{tag: which} = assigns, socket) do
    {:ok, assign(socket, Map.merge(assigns, %{card: extract(which)}))}
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
        <h1 class="text=center">Tag Explorer</h1>
        <hr/>
        <div class="grid grid-cols-4 mt-10">
        <%= @card["tags"] %>
      </div>
      </div>
    """
  end

  defp extract(:all) do
    Catenary.dets_open(:tags)

    tags =
      :dets.match(:tags, :"$1")
      |> Enum.reduce([], fn [{f, i} | _], a ->
        case is_binary(f) do
          true -> [{Enum.count(i), f} | a]
          false -> a
        end
      end)
      |> Enum.sort(:desc)
      |> Enum.uniq()
      |> to_links()

    Catenary.dets_close(:tags)
    %{"tags" => tags}
  end

  defp extract(_), do: :none

  defp to_links(tags) do
    tags
    |> Enum.map(fn {c, t} ->
      "<div class=\"text-orange-600 dark:text-amber-200\"><button value=\"" <>
        t <>
        "\" phx-click=\"view-tag\">" <> t <> " (" <> Integer.to_string(c) <> ")</button></div>"
    end)
    |> Phoenix.HTML.raw()
  end
end
