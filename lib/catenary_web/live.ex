defmodule CatenaryWeb.Live do
  use CatenaryWeb, :live_view
  @about_an_hour 3_599_969

  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @about_an_hour)

    opts = []

    {:ok, assign(socket, opts)}
  end

  def render(assigns) do
    ~L"""
    <section class="phx-hero" id="page-live" phx-hook="weback">
    <div class="mx-2 grid grid-cols-1 md:grid-cols-4 gap-10 justify-center font-mono">
      <h1>Catenary</h1>
    </div>
    """
  end
end
