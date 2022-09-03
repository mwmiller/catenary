defmodule Catenary.Live.Navigation do
  use Phoenix.LiveComponent

  @impl true
  def update(assigns, socket) do
    # As things expand, we'll use this info to build a proper
    # interface to navigate.
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~L"""
      <div class="min-w-full font-sans text-xl">

         <button value="prev-author" phx-click="nav">⇧</button>
         <button value="prev-entry" phx-click="nav">☚</button>
         <button value="next-entry" phx-click="nav">☛</button>
         <button value="next-author" phx-click="nav">⇩</button>
      </div>
    """
  end
end
