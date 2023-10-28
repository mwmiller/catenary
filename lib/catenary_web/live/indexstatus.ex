defmodule Catenary.Live.IndexStatus do
  use Phoenix.LiveComponent
  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div class="status flex flex-row font-mono text-xs text-center mx-1 w-max">
      <%= for s <- @indexing do %>
        <div class="flex-auto p-1"><%= s %></div>
      <% end %>
    </div>
    """
  end
end
