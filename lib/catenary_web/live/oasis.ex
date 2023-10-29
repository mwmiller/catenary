defmodule Catenary.Live.OasisExplorer do
  use Phoenix.LiveComponent
  alias Catenary.Display

  @impl true
  def update(assigns, socket) do
    {:ok, nodes} = assigns.oases

    {:ok,
     assign(socket,
       aliases: assigns.aliases,
       nodes: nodes,
       opened: assigns.opened
     )}
  end

  @impl true

  def render(%{nodes: []} = assigns) do
    ~L"""
    <%= Display.explore_wrap("Oasis") %>
    <div class="font-mono text-xs my-2">
      <div class="my-1 p-1 bg-slate-200 dark:bg-slate-700">
        No recent oases found.
        <%= if @opened == 0 do %>
        <button phx-click="init-connect" phx-disable-with="↯ trying ↯">
        ⇆ try fallback host ⇆</span></button>
        <% else %>
        ⥀ attempting sync ⥀
        <% end %>
      </div>
    </div>
    </div>
    """
  end

  def render(assigns) do
    ~L"""
     <div id="oasisexplore-wrap" class="col-span-2 overflow-y-auto max-h-screen m-2 p-x-2">
      <h1>Oasis Explorer</h1>
      <hr/>
    <div class="font-mono text-xs py-2">
      <%= for {recent, index}  <- Enum.with_index(@nodes) do %>
        <div class="my-1 p-1 <%= case rem(index, 2)  do
        0 ->  "bg-zinc-200 dark:bg-stone-700"
        1 -> "bg-slate-200 dark:bg-slate-700"
      end %>">
          <%= if op = recent["operator"], do:
            Display.scaled_avatar(op, 1, ["m-1", "float-left", "align-middle"]) %>
          <%= Display.scaled_avatar(elem(recent.id, 0), 2, ["m-1", "float-right", "align-middle"]) %>
        <p><%= recent["name"] %> (<%= Display.linked_author(elem(recent.id, 0), @aliases) %>)
        <%= if recent.connected do %>
          ⥀
        <% else %>
        <button phx-click="connect" phx-disable-with="↯" value="<%= Catenary.index_to_string(recent.id) %>">⇆</button>
        <% end %>
        </div>
      <% end %>
    </div>
        </div>
    """
  end
end
