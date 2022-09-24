defmodule Catenary.MenuMaker do
  defmacro generate(name, items) do
    quote bind_quoted: [name: name, items: items] do
      defmodule name do
        use Desktop.Menu
        @impl true
        def mount(menu) do
          {:ok, menu}
        end

        @impl true
        for {_, defs} <- items do
          for %{command: cmd, action: act} <- defs do
            action_map = Macro.escape(act)

            def handle_event(unquote(cmd), menu) do
              Phoenix.PubSub.local_broadcast(Catenary.PubSub, "ui", unquote(action_map))

              {:noreply, menu}
            end
          end
        end

        def handle_event("reset", menu) do
          # Back to the starting URI
          # If it's not a safe space, we don't have one
          Desktop.Window.show(CatenaryWindow, CatenaryWeb.Endpoint.url())
          menu
        end

        def handle_event("quit", menu), do: Desktop.Window.quit()

        @impl true
        def handle_info(stuff, menu) do
          IO.inspect({:unhandled_menu, stuff})
          {:noreply, menu}
        end

        @impl true
        def render(assigns) do
          unquote(Catenary.MenuMaker.actual_bar(items))
        end
      end
    end
  end

  def actual_bar(items), do: actual_bar(items, "<menubar>")
  def actual_bar([], acc), do: acc <> "</menubar>"

  def actual_bar([{label, items} | rest], acc) do
    actual_bar(
      rest,
      acc <>
        "<menu label=\"" <> label <> "\">" <> menu_items(items) <> "</menu>"
    )
  end

  defp menu_items(items, acc \\ "")
  defp menu_items([], acc), do: acc
  defp menu_items([:rule | rest], acc), do: menu_items(rest, acc <> "<hr/>")

  defp menu_items([%{label: label, command: command} | rest], acc),
    do: menu_items(rest, acc <> "<item onclick=\"" <> command <> "\">" <> label <> "</item>")
end
