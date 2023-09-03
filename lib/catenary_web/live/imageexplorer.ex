defmodule Catenary.Live.ImageExplorer do
  require Logger
  use Phoenix.LiveComponent

  @impl true
  def update(%{entry: which, aliases: aliases} = assigns, socket) do
    {:ok, assign(socket, Map.merge(assigns, %{entry: which, card: extract(aliases)}))}
  end

  @impl true
  def render(%{card: :none} = assigns), do: Catenary.GeneriCard.no_data_card(assigns)

  def render(%{card: :error} = assigns), do: Catenary.GeneriCard.error_card(assigns)

  def render(assigns) do
    ~L"""
     <div id="imageexplore-wrap" class="col-span-2 overflow-y-auto max-h-screen m-2 p-x-2">
      <h1>Image Explorer</h1>
      <%= for a <- [:type, :poster, :shown, :any] do %>
        <button value="<%= a %>" phx-click="arrange" phx-target="<%= @myself %>"><p class="text-amber-900 dark:text-amber-100 <%= if @entry == a, do: "underline" %>"><%= a %></p></button>

        <% end %>
        <%= for {t, g} <-  @card[@entry] do %>
         <h4><%= t %></h4>
         <div class="flex flex-row flex-wrap mt-7 mx-auto">
         <%= for i <- g do %>
          <%= i %>
         <% end %>
         </div>
       <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("arrange", %{"value" => how}, socket) do
    {:noreply, assign(socket, entry: String.to_existing_atom(how))}
  end

  defp extract(aliases) do
    case :ets.lookup(:images, :map) do
      [{:map, full_map}] -> full(Map.to_list(full_map), aliases)
      _ -> {"none", []}
    end
  end

  defp full(map, aliases, acc \\ [])
  defp full([], _, acc), do: acc |> Enum.into(%{})

  defp full([{key, subitems} | rest], aliases, acc),
    do: full(rest, aliases, [{key, grouped(Map.to_list(subitems), aliases)} | acc])

  defp grouped(images, aliases, acc \\ [])
  defp grouped([], _, acc), do: acc

  defp grouped([{title, items} | rest], aliases, acc) do
    # This is probably a bad assumption long term
    # but all of this is very hasky anyway
    t =
      case is_binary(title) and byte_size(title) == 43 do
        true -> Catenary.short_id(title, aliases)
        false -> title
      end

    grouped(rest, aliases, [{t, displayable(items)} | acc])
  end

  defp displayable(entries, acc \\ [])
  defp displayable([], images), do: images

  defp displayable([{src, entry} | rest], images) do
    img_tag = "<img class=\"w-20 m-1\" src=" <> src <> ">"

    val =
      ("<div class=\"flex-auto\">" <> Catenary.view_entry_button(entry, img_tag) <> "</div>")
      |> Phoenix.HTML.raw()

    displayable(rest, [val | images])
  end
end
