defmodule Catenary.Live.ImageExplorer do
  require Logger
  use Phoenix.LiveComponent

  @impl true
  def update(%{entry: which} = assigns, socket) do
    {:ok, assign(socket, Map.merge(assigns, %{card: extract(which)}))}
  end

  @impl true
  def render(%{card: :none} = assigns), do: Catenary.GeneriCard.no_data_card(assigns)

  def render(%{card: :error} = assigns), do: Catenary.GeneriCard.error_card(assigns)

  def render(assigns) do
    ~L"""
     <div id="imageexplore-wrap" class="col-span-2 overflow-y-auto max-h-screen m-2 p-x-2">
      <h1 class="text=center">Image Explorer</h1>
        <%= for g <-  @card["images"] do %>
      <div class="flex flex-row min-w-full p-5">
        <%= g %>
      </div>
      <% end %>
    </div>
    """
  end

  defp extract(:all) do
    :ets.lookup(:images, :all)
    |> then(fn
      [{:all, items}] -> displayable(items, [])
      _ -> []
    end)
    |> then(fn images -> %{"images" => images} end)
  end

  defp extract(_), do: :none

  defp displayable([], images), do: images

  defp displayable([{src, entry} | rest], images) do
    img_tag = "<img src=" <> src <> ">"

    val =
      ("<div class=\"flex-auto\">" <> Catenary.view_entry_button(entry, img_tag) <> "</div>")
      |> Phoenix.HTML.raw()

    displayable(rest, [val | images])
  end
end
