defmodule Catenary.Live.TagExplorer do
  require Logger
  use Phoenix.LiveComponent
  alias Catenary.Display

  @impl true
  def update(%{entry: which} = assigns, socket) do
    {:ok, assign(socket, Map.merge(assigns, %{card: extract(which)}))}
  end

  @impl true
  def render(%{card: :none} = assigns), do: Catenary.GeneriCard.no_data_card(assigns)

  def render(%{card: :error} = assigns), do: Catenary.GeneriCard.error_card(assigns)

  def render(assigns) do
    ~L"""
    <%= Display.explore_wrap("tag") %>
        <%= for g <-  @card["tags"] do %>
      <div class="grid grid-cols-3 mt-10">
        <%= g %>
      </div>
      <% end %>
    </div>
    """
  end

  defp extract(:all) do
    :ets.lookup(:tags, :display)
    |> then(fn
      [{_, items}] -> link_groups(items, [])
      _ -> []
    end)
    |> then(fn tags -> %{"tags" => tags} end)
  end

  defp extract(_), do: :none

  defp link_groups([], acc), do: Enum.reverse(acc)
  defp link_groups([tags | rest], acc), do: link_groups(rest, [to_links(tags) | acc])

  defp to_links(tags) do
    tags
    |> Enum.map(fn {t, _c} ->
      "<div><button value=\"" <>
        t <>
        "\" phx-click=\"view-tag\"><p class=\"tighter text-amber-900 dark:text-amber-100\">" <>
        t <> "</p></button></div>"
    end)
    |> Phoenix.HTML.raw()
  end
end
