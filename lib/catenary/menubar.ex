defmodule Catenary.MenuBar do
  use Desktop.Menu
  @impl true
  def mount(menu) do
    menu = assign(menu, iconset: :png)
    {:ok, menu}
  end

  @impl true
  def handle_event(command, menu) do
    nm =
      case command do
        <<"quit">> ->
          Desktop.Window.quit()

        <<"png">> ->
          Phoenix.PubSub.local_broadcast(Catenary.PubSub, "ui", %{icons: :png})
          assign(menu, iconset: :png)

        <<"svg">> ->
          Phoenix.PubSub.local_broadcast(Catenary.PubSub, "ui", %{icons: :svg})
          assign(menu, iconset: :svg)

        <<"dashboard">> ->
          Phoenix.PubSub.local_broadcast(Catenary.PubSub, "ui", %{view: :dashboard})
          menu
      end

    {:noreply, nm}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <menubar>
      <menu label="File">
          <item onclick="dashboard">Open dashboard</item>
          <item onclick="quit">Quit</item>
      </menu>
      <menu label="Icons">
        <%= if @iconset == :png do %>
        <item onclick="png" type="checkbox" checked>Blocky</item>
        <item onclick="svg" type="checkbox">Curvy</item>
        <% else %>
        <item onclick="png" type="checkbox">Blocky</item>
        <item onclick="svg" type="checkbox" checked>Curvy</item>
        <% end %>
      </menu>
    </menubar>
    """
  end
end
