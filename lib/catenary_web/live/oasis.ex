defmodule Catenary.Live.OasisBox do
  use Phoenix.LiveComponent
  @impl true
  def update(%{connection: {_, info}} = assigns, socket) do
    {:ok, assign(socket, nodes: [info], iconset: assigns.iconset, connected: true)}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, nodes: assigns.watering, iconset: assigns.iconset, connected: false)}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div>
      <%= for {recent, index}  <- Enum.with_index(@nodes) do %>
        <div class="m-2 <%= case rem(index, 2)  do
        0 ->  "bg-emerald-200 dark:bg-cyan-700"
        1 -> "bg-emerald-400 dark:bg-sky-700"
      end %>"><img class="m-1 float-right align-middle" src="<%= Catenary.identicon(elem(recent.id, 0), @iconset, 2)%>">
        <p><%= recent["name"] %> (<%= Catenary.short_id(elem(recent.id, 0)) %>)
        &nbsp;&nbsp;
        <%= if @connected do %>
          syncing...
        <% else %>
        <button phx-click="connect" value="<%= recent.id |>  Tuple.to_list |> Enum.join("⋀") %>">⇆</button></p>
        <% end %>

        </div>
      <% end %>
    </div>
    """
  end
end
