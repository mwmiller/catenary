defmodule Catenary.GeneriCard do
  use Phoenix.LiveComponent

  # I just want the sigil, but the compiler complains about
  # lack of implementations
  @impl true
  def render(assigns) do
    ~L"""
    """
  end

  def no_data_card(assigns) do
    ~L"""
      <div id="no-data" class="min-w-full font-sans col-span-2 max-h-screen m-2">
        <h1>No data just yet</h1>
      </div>
    """
  end

  def error_card(assigns) do
    ~L"""
      <div id="no-data" class="min-w-full font-sans col-span-2 max-h-screen m-2">
        <h1>Unrenderable card</h1>
      </div>
    """
  end
end
