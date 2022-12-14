defmodule Catenary.Live.Ident do
  use Phoenix.LiveComponent

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div class="flex flex-row align-top my-2 min-w-full font-sans">
      <div class="flex-auto"><button phx-click="to-im" phx-target="<%= @myself %>"><%= @clump_id %>:</button></div>
      <div class="flex-auto"><%= Catenary.linked_author(@identity, @aliases) %></div>
      <div class="flex-1/2"><img src="<%= Catenary.identicon(@identity, 4) %>"></div>
      <br/>
    </div>
    """
  end

  # This seems a bit convoluted, but I want to reuse the menu logic
  @impl true
  def handle_event("to-im", _, socket) do
    Phoenix.PubSub.local_broadcast(Catenary.PubSub, "ui", %{view: :prefs, entry: :none})
    {:noreply, socket}
  end
end
