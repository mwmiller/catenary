defmodule Catenary.Live.UnshownExplorer do
  require Logger
  use Phoenix.LiveComponent

  @impl true
  def update(%{which: which, clump_id: clump_id} = assigns, socket) do
    {:ok, assign(socket, Map.merge(assigns, %{card: extract(which, clump_id)}))}
  end

  @impl true
  def render(%{card: :none} = assigns) do
    ~L"""
      <div class="min-w-full font-sans row-span-full">
        <h1></h1>
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
     <div id="unshownexplore-wrap" class="col-span-2 overflow-y-auto max-h-screen m-2 p-x-2">
      <h1 class="text=center">Unshown Explorer</h1>
      <hr/>
      <div class="grid grid-cols-5 mt-5">
        <%= @card["unshown"] %>
      </div>
    </div>
    """
  end

  defp extract(:all, clump_id) do
    shown = Catenary.Preferences.get(:shown) |> Map.get(clump_id, MapSet.new())

    unshown =
      Baobab.all_entries(clump_id)
      |> MapSet.new()
      |> MapSet.difference(shown)
      |> MapSet.to_list()
      |> to_links
      |> Phoenix.HTML.raw()

    %{"unshown" => unshown}
  end

  defp extract(_, _), do: :none

  defp to_links([]), do: "<div>All caught up</div>"

  defp to_links(unshown) do
    unshown
    |> Enum.map(fn e -> "<div>" <> Catenary.entry_icon_link(e, 4) <> "</div>" end)
  end
end
