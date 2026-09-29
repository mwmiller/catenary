defmodule CatenaryWeb.LiveTest do
  use CatenaryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "renders the three-column layout with the inner component" do
    {:ok, _view, html} = live(build_conn(), "/")

    assert html =~ "max-h-screen w-full flex justify-center px-2 py-2 gap-3"
    assert html =~ "w-full max-w-4xl"
    # the implicit inner block renders the active view's component
    assert html =~ "content-wrap"
  end

  test "back and forward buttons have a single merged class" do
    {:ok, view, _html} = live(build_conn(), "/")

    back = view |> element("button[title=Back]") |> render()
    fwd = view |> element("button[title=Forward]") |> render()

    # A single class attribute, with both the stack color and the static styles
    assert Regex.scan(~r/class="/, back) |> length() == 1
    assert back =~ "btn-icon"
    assert Regex.scan(~r/class="/, fwd) |> length() == 1
    assert fwd =~ "btn-icon"
  end

  test "the unshown view button is not flagged when the clump has no entries" do
    {:ok, view, _html} = live(build_conn(), "/")

    unshown = view |> element("button[title=Unshown]") |> render()

    # The test clump has no entries, so the "you have unshown entries" badge
    # must not be applied. This also pins that state_set/3 still assigns
    # has_unshown at all: the button below is its only consumer, and a missing
    # assign would raise while rendering it.
    refute unshown =~ "btn-icon-badge"
    assert unshown =~ "btn-icon"
  end

  test "the explorebar marks the current view without recolouring the glyph" do
    {:ok, view, _html} = live(build_conn(), "/")

    unshown = view |> element("button[title=Unshown]") |> render()
    refute unshown =~ "btn-icon-current"
    refute unshown =~ ~s(aria-current="page")

    view |> element("button[title=Tags]") |> render_click()

    tags = view |> element("button[title=Tags]") |> render()

    # "You are here" is a background fill plus aria-current, never a glyph
    # colour: a colour here would collide with any other highlight on the
    # same button, and the layer order would silently pick the loser.
    assert tags =~ "btn-icon-current"
    assert tags =~ ~s(aria-current="page")
    refute tags =~ "text-amber"
  end

  test "the clump id is a passive label; settings and profile are explicit buttons" do
    {:ok, view, html} = live(build_conn(), "/")

    # The clump id is context, not a navigation button: settings (⚙) and the
    # self-profile (avatar + name) are explicit controls, and no explorebar
    # control sends a "prefs" toview anymore.
    assert has_element?(view, "span[title=Clump]")
    assert has_element?(view, "button[aria-label=Settings]")
    assert has_element?(view, ~s(button[aria-label="Your profile"]))
    assert has_element?(view, "button[title=Clump]") == false
    assert has_element?(view, "button[title=Home]") == false
    refute html =~ ~s(value="prefs")
  end

  test "the settings cog opens prefs and carries the current-mode marker" do
    {:ok, view, _html} = live(build_conn(), "/")

    view |> element("button[title=Tags]") |> render_click()
    refute view |> element("button[aria-label=Settings]") |> render() =~ ~s(aria-current="page")

    view |> element("button[aria-label=Settings]") |> render_click()

    settings = view |> element("button[aria-label=Settings]") |> render()
    assert settings =~ ~s(aria-current="page")
    # Settings is a mode, so the current-state marker is the amber fill only
    assert settings =~ "bg-amber-100"
  end

  test "native-menu Preferences opens settings as a mode, not a history entry" do
    {:ok, view, _html} = live(build_conn(), "/")

    # Toview navigation records no history, so if Preferences also stays off
    # the stack the Back button remains disabled through the whole trip.
    view |> element("button[title=Tags]") |> render_click()

    render_hook(view, "menu", %{"view" => "prefs", "entry" => "none"})

    assert view |> element("button[aria-label=Settings]") |> render() =~ ~s(aria-current="page")
    back = view |> element("button[title=Back]") |> render()
    assert back =~ "disabled"
  end

  test "the reindex button sits outside the index indicator strip" do
    {:ok, view, _html} = live(build_conn(), "/")

    strip = view |> element(".index-strip") |> render()

    # The indicators are a read-out and reindexing is an action, so they must
    # not share a background: the button is a sibling of the strip, not a
    # child, and the strip carries only the pills. A generic div may not take
    # aria-label, so the accessible name comes from sr-only text instead.
    assert strip =~ ~s(class="sr-only">Challenges indexed)
    refute strip =~ "aria-label"
    refute strip =~ "Reindex"
    assert has_element?(view, ".index-strip button[aria-label=Reindex]") == false
    assert has_element?(view, "button[aria-label=Reindex]")
  end

  test "compose triggers report the panel state and drive it open and shut" do
    {:ok, view, html} = live(build_conn(), "/")
    trigger = "#compose-trigger-journal"

    closed = render(element(view, trigger))

    # Each opener is hand-built string concatenation (post_button_for/1) or
    # HEEx, so pin the whole aria contract: the trigger names the panel it
    # controls, and reports that the panel is currently shut.
    assert closed =~ ~s(phx-click="toggle-journal")
    assert closed =~ ~s(aria-expanded="false")
    assert closed =~ ~s(aria-controls="compose-panel")
    refute html =~ ~s(id="compose-panel")

    # Opening sets aria-expanded and renders the panel the id points at.
    html = view |> element(trigger) |> render_click()
    assert html =~ ~s(id="compose-panel")
    assert render(element(view, trigger)) =~ ~s(aria-expanded="true")

    # Re-picking the active opener closes it again (the toggle- clause in Live
    # maps a repeat pick to :none), and the panel unmounts.
    html = view |> element(trigger) |> render_click()
    refute html =~ ~s(id="compose-panel")
    assert render(element(view, trigger)) =~ ~s(aria-expanded="false")
  end
end
