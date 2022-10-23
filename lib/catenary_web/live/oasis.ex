defmodule Catenary.Live.OasisBox do
  use Phoenix.LiveComponent
  @impl true
  def update(assigns, socket) do
    {:ok,
     assign(socket,
       aliases: assigns.aliases,
       nodes: assigns.oases,
       connected: Enum.map(assigns.connections, &id_mapper/1)
     )}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div class="font-mono text-xs my-2">
      <%= for {recent, index}  <- Enum.with_index(@nodes) do %>
        <div class="my-1 p-1 <%= case rem(index, 2)  do
        0 ->  "bg-zinc-200 dark:bg-stone-700"
        1 -> "bg-slate-200 dark:bg-slate-700"
      end %>"><img class="m-1 float-right align-middle" src="<%= Catenary.identicon(elem(recent.id, 0), 2)%>">
        <p><%= recent["name"] %> (<%= Catenary.linked_author(elem(recent.id, 0), @aliases) %>)
        <%= if recent.id in @connected do %>
          ⥀
        <% else %>
        <button phx-click="connect" phx-disable-with="↯" value="<%= Catenary.index_to_string(recent.id) %>">⇆</button>
        <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp id_mapper({_, %{id: id}}), do: id
  defp id_mapper(_), do: ""
end
