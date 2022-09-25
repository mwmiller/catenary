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
     <div id="tagexplore-wrap" class="col-span-2 overflow-y-auto max-h-screen m-2 p-x-2">
      <h1 class="text=center">Tag Explorer</h1>
      <hr/>
      <div class="grid grid-cols-3 mt-10">
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
        case f do
          {"", t} -> [{t, Enum.any?(i, fn {_t, e} -> not Catenary.Preferences.shown?(e) end)} | a]
          _ -> a
        end
      end)
      |> Enum.uniq()
      |> Enum.shuffle()
      |> to_links()

    Catenary.dets_close(:tags)
    %{"tags" => tags}
  end

  defp extract(_), do: :none

  defp to_links(tags) do
    tags
    |> Enum.map(fn {t, n} ->
      "<div><button value=\"" <>
        t <>
        "\" phx-click=\"view-tag\"><p class=\"tighter text-orange-600 dark:text-amber-200 " <>
        new_or_not(n) <> "\">" <> t <> "</p></button></div>"
    end)
    |> Phoenix.HTML.raw()
  end

  defp new_or_not(true), do: "underline decoration-dotted"
  defp new_or_not(false), do: ""
end
