defmodule Catenary.Live.OasisBox do
  use Phoenix.LiveComponent
  @impl true
  def update(assigns, socket) do
    {:ok,
     assign(socket,
       indexing: assigns.indexing,
       nodes: assigns.watering,
       iconset: assigns.iconset,
       connected: Enum.map(assigns.connections, fn {_, m} -> m.id end)
     )}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div class="font-mono text-xs">
      <%= for {recent, index}  <- Enum.with_index(@nodes) do %>
        <div class="my-1 p-1 <%= case rem(index, 2)  do
        0 ->  "bg-emerald-200 dark:bg-cyan-700"
        1 -> "bg-emerald-400 dark:bg-sky-700"
      end %>"><img class="m-1 float-right align-middle" src="<%= Catenary.identicon(elem(recent.id, 0), @iconset, 2)%>">
        <p><%= recent["name"] %> (<%= Catenary.short_id(elem(recent.id, 0)) %>)
        <span>
        <%= if recent.id in @connected do %>
          ⥀
        <% else %>
        <button phx-click="connect" phx-disable-with="↯" value="<%= Catenary.index_to_string(recent.id) %>">⇆</button></p>
        <% end %>
        </span>

        </div>
      <% end %>
      <p class="text-center"><%= if @indexing, do: "𝍂", else: "∴" %></p>
    </div>
    """
  end
end
