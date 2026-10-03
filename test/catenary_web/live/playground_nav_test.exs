defmodule CatenaryWeb.Live.PlaygroundNavTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Catenary.Live.PlaygroundNav

  # The rail only talks: every command here is a message to the LiveView
  # that holds the draft. What the panel's words become — a compiled
  # module, four entries, a trace line — is tested against that LiveView
  # and against the writer instead.

  defp nav(assigns) do
    {:ok, socket} =
      PlaygroundNav.update(Map.put(assigns, :id, :playground_nav), %Phoenix.LiveView.Socket{})

    socket
  end

  test "the panel opens on its trigger and shuts again" do
    socket = nav(%{publish: false})

    refute socket.assigns.publish

    {:noreply, socket} = PlaygroundNav.handle_event("toggle-publish", %{}, socket)
    assert socket.assigns.publish

    {:noreply, socket} = PlaygroundNav.handle_event("toggle-publish", %{}, socket)
    refute socket.assigns.publish
  end

  test "submitting the panel forwards its words and shuts the panel" do
    socket = nav(%{publish: true})

    words = %{
      "slug" => "hello-app",
      "title" => "Hello",
      "description" => "the fixture",
      "version" => "1.0.0"
    }

    {:noreply, socket} = PlaygroundNav.handle_event("publish-app", words, socket)

    assert_received {:playground_publish, ^words}
    refute socket.assigns.publish
  end

  test "the closed rail offers no panel, the open one offers the form" do
    # `render_component/2` injects `@myself` only for an identified
    # component, which is what the trigger's `phx-target` reads.
    refute render_component(PlaygroundNav, %{id: :playground_nav, publish: false}) =~
             "publish-form"

    html = render_component(PlaygroundNav, %{id: :playground_nav, publish: true})

    assert html =~ "publish-form"
    assert html =~ ~s(name="slug")
    assert html =~ ~s(name="title")
    assert html =~ ~s(name="description")
    assert html =~ ~s(name="version")
    # The trigger only opens the panel; the submit is the button that
    # writes, so it is the amber one.
    assert html =~ "btn-primary"
    assert html =~ "Publish</button>"
  end
end
