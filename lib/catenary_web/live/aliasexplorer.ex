defmodule Catenary.Live.AliasExplorer do
  require Logger
  use Phoenix.LiveComponent

  @impl true
  def update(%{alias: which} = assigns, socket) do
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
      <h1 class="text=center">Alias Explorer</h1>
      <hr/>
      <div class="grid grid-cols-3 mt-10">
        <%= @card["aliases"] %>
      </div>
    </div>
    """
  end

  defp extract(:all) do
    Catenary.dets_open(:aliases)
    G

    aliases =
      :dets.match(:aliases, :"$1")
      |> Enum.sort_by(fn [{_a, n}] -> String.downcase(n) end)
      |> to_links()

    Catenary.dets_close(:aliases)
    %{"aliases" => aliases}
  end

  defp extract(_), do: :none

  defp to_links(aliases) do
    aliases
    |> Enum.map(fn [{a, _}] ->
      {:safe, html} = Catenary.linked_author(a)
      "<div>" <> html <> "</div>"
    end)
    |> Phoenix.HTML.raw()
  end
end
