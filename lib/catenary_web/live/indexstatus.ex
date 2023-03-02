defmodule Catenary.Live.IndexStatus do
  use Phoenix.LiveComponent
  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div class="flex flex-row font-mono text-xs text-center my-2 min-w-full">
      <%= for s <- @indexing do %>
        <div class="flex-auto"><%= s %></div>
      <% end %>
    </div>
    """
  end
end
