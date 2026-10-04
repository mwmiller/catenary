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
    assert html =~ "Release</button>"
  end

  test "the fixture panel opens on its trigger and shuts again" do
    socket = nav(%{fixture: :self})

    refute socket.assigns.fixture_open

    {:noreply, socket} = PlaygroundNav.handle_event("toggle-fixture", %{}, socket)
    assert socket.assigns.fixture_open

    {:noreply, socket} = PlaygroundNav.handle_event("toggle-fixture", %{}, socket)
    refute socket.assigns.fixture_open
  end

  test "the picked fixture is a message up, never state kept on the rail" do
    socket = nav(%{fixture: :self})

    {:noreply, _socket} =
      PlaygroundNav.handle_event("pick-fixture", %{"fixture" => "sample"}, socket)

    assert_received {:playground_fixture, "sample"}

    {:noreply, socket} =
      PlaygroundNav.handle_event("pick-fixture", %{"fixture" => "self"}, socket)

    assert_received {:playground_fixture, "self"}

    # A value outside the pair is ignored rather than forwarded as-is.
    {:noreply, _socket} =
      PlaygroundNav.handle_event("pick-fixture", %{"fixture" => "elsewhere"}, socket)

    refute_received {:playground_fixture, _}
  end

  test "the closed rail offers no fixture panel, the open one offers both choices" do
    # The trigger's own `aria-controls` names the panel either way, so the
    # panel's identity is the `id` rather than the string it is named by.
    refute render_component(PlaygroundNav, %{id: :playground_nav, fixture: :self}) =~
             ~s(id="fixture-panel")

    html =
      render_component(PlaygroundNav, %{
        id: :playground_nav,
        fixture: :self,
        fixture_open: true
      })

    assert html =~ ~s(id="fixture-panel")
    assert html =~ ~s(name="fixture")
    assert html =~ ~s(value="self")
    assert html =~ ~s(value="sample")
    # This identity is the default: its radio is the checked one.
    assert html =~ ~s(value="self" checked)
    refute html =~ ~s(value="sample" checked)
  end

  test "the checked choice follows the fixture the run is pointed at" do
    html =
      render_component(PlaygroundNav, %{
        id: :playground_nav,
        fixture: {:sample, String.duplicate("1", 43)},
        fixture_open: true
      })

    assert html =~ ~s(value="sample" checked)
    refute html =~ ~s(value="self" checked)
  end
end
