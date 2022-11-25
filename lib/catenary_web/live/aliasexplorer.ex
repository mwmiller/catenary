defmodule Catenary.Live.AliasExplorer do
  require Logger
  use Phoenix.LiveComponent

  @impl true
  def update(%{alias: which, aliases: aliases} = assigns, socket) do
    {:ok, assign(socket, Map.merge(assigns, %{card: extract(which, aliases)}))}
  end

  @impl true
  def render(%{card: :none} = assigns), do: Catenary.GeneriCard.no_data_card(assigns)

  def render(%{card: :error} = assigns), do: Catenary.GeneriCard.error_card(assigns)

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

  defp extract(:all, {_, am} = as) do
    aliases =
      am
      |> Map.to_list()
      |> Enum.sort_by(fn {_a, n} -> String.downcase(n) end)
      |> to_links(as)

    %{"aliases" => aliases}
  end

  defp extract(_, _), do: :none

  defp to_links(aliases, as) do
    aliases
    |> Enum.map(fn {a, _} ->
      {:safe, html} = Catenary.linked_author(a, as)
      "<div>" <> html <> "</div>"
    end)
    |> Phoenix.HTML.raw()
  end
end
