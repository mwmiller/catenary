defmodule Catenary.Live.Ident do
  use Phoenix.LiveComponent

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div class="align-top min-w-full font-sans">
      <div class="flex flex-row space-x-4">
        <div class="flex-auto"><button phx-click="to-im" phx-target="<%= @myself %>">Logging as:</button></div>
         <div class="flex-auto"><%= Catenary.linked_author(@identity) %></div>
         <div class="flex-1/2"><img src="<%= Catenary.identicon(@identity, 4) %>"></div>
       <div>
      <br/>
    </div>
    """
  end

  # This seems a bit convoluted, but I want to reuse the menu logic
  def handle_event("to-im", _, socket) do
    Phoenix.PubSub.local_broadcast(Catenary.PubSub, "ui", %{view: :idents})
    {:noreply, socket}
  end
end
