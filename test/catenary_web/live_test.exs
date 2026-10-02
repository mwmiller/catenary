defmodule CatenaryWeb.LiveTest do
  use CatenaryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Catenary.Preferences

  setup do
    # The publish tests below write into the test clump, which persists across
    # runs. The unshown-entries badge reads the whole store, so declare
    # whatever is already there seen rather than let a leftover entry light
    # the badge for the tests that follow.
    Preferences.mark_all_entries(:shown)

    # Every test here boots at "/" and the navigation tests below change the
    # persisted view and entry, which is what the next test would boot into.
    # Hand each one the same starting screen.
    starting = %{view: Preferences.get(:view), entry: Preferences.get(:entry)}

    on_exit(fn ->
      Preferences.set(:view, starting.view)
      Preferences.set(:entry, starting.entry)
    end)

    :ok
  end

  defp entries, do: Baobab.all_entries(Preferences.get(:clump_id))

  # The count assertions below print this when they fail, so a CI failure says
  # which log wrote an entry rather than only that one turned up. Entries are
  # {author, log_id, seqnum} tuples.
  defp stored, do: entries()

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

  test "the profile button marks your own profile with the standard chip" do
    {:ok, view, _html} = live(build_conn(), "/")

    view |> element("button[title=Tags]") |> render_click()

    profile = view |> element(~s(button[aria-label="Your profile"])) |> render()
    refute profile =~ ~s(aria-current="page")
    refute profile =~ "bg-amber-100"
    # unshown mentions use the dot badge like every other button, never a
    # recoloured label that collides with the current-state fill
    refute profile =~ "text-amber-600"

    view |> element(~s(button[aria-label="Your profile"])) |> render_click()

    profile = view |> element(~s(button[aria-label="Your profile"])) |> render()
    assert profile =~ ~s(aria-current="page")
    assert profile =~ "bg-amber-100"
  end

  test "settings has a page heading and labels its rename inputs" do
    {:ok, view, _html} = live(build_conn(), "/")

    view |> element("button[aria-label=Settings]") |> render_click()

    assert view |> element("h1") |> render() =~ "Settings"
    assert has_element?(view, ~s(input[aria-label^="Rename identity"]))
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

  test "the native Go menu opens the playground as a navigation" do
    {:ok, view, _html} = live(build_conn(), "/")

    # The same destination as the listings header's New app button, so it
    # arrives with history behind it rather than as a mode like Settings —
    # Back is live and returns to where the menu was opened from.
    view |> element("button[title=Tags]") |> render_click()

    render_hook(view, "menu", %{"view" => "playground", "entry" => "all"})

    assert view |> element("h1") |> render() =~ "Playground"
    refute view |> element("button[title=Back]") |> render() =~ "disabled"
  end

  test "the playground rail carries a .wasm picker alongside Run and Stop" do
    Preferences.set(:view, :playground)
    Preferences.set(:entry, :all)

    {:ok, view, html} = live(build_conn(), "/")

    # Glyph, tooltip and the name the input announces: the picker is a file
    # input behind ⇥ — the same glyph Preferences uses to import a file from
    # disk (⇤ is its export) — and the pane it feeds is the one with the
    # trace on.
    assert html =~ "⇥"
    refute html =~ "⇩"
    assert has_element?(view, ~s(label[title="Import a .wasm file"][phx-hook="WasmDropin"]))
    assert has_element?(view, ~s(input[type=file][accept=".wasm,application/wasm"]))
    assert has_element?(view, ~s(input[aria-label="Import a .wasm file into the run pane"]))
    assert has_element?(view, "#playground-pane[data-trace][data-worker-src]")
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

  test "a compose panel drops away with its trigger when the screen changes" do
    {:ok, view, _html} = live(build_conn(), "/")

    # A profile screen offers the alias trigger; the tags screen does not.
    view |> element(~s(button[aria-label="Your profile"])) |> render_click()
    html = render_hook(view, "toggle-alias", %{})
    assert html =~ ~s(id="compose-panel")
    assert has_element?(view, "#compose-trigger-alias")

    view |> element("button[title=Tags]") |> render_click()

    # Gone with its trigger, rather than left as a frame around nothing.
    refute has_element?(view, "#compose-trigger-alias")
    refute has_element?(view, "#compose-panel")
  end

  test "a panel the screen does not offer never draws its frame" do
    {:ok, view, _html} = live(build_conn(), "/")

    view |> element("button[title=Tags]") |> render_click()

    # The reply trigger is not rendered on this screen, so neither is its
    # panel — not even when the toggle event arrives anyway.
    refute has_element?(view, "#compose-trigger-reply")
    refute render_hook(view, "toggle-reply", %{}) =~ ~s(id="compose-panel")

    # While a panel this screen does offer still opens.
    assert render_hook(view, "toggle-journal", %{}) =~ ~s(id="compose-panel")
  end

  test "publishing closes the compose panel and debounces a repeat" do
    {:ok, view, _html} = live(build_conn(), "/")
    count = length(entries())

    view |> element("#compose-trigger-journal") |> render_click()
    assert has_element?(view, "#posting-form")

    payload = %{"log_id" => "360360", "title" => "One", "body" => "first body"}
    html = view |> element("#posting-form") |> render_submit(payload)

    # The panel leaves with the publish: no re-enabled button to click again,
    # and no form left re-rendered against the entry that was just created.
    refute html =~ ~s(id="posting-form")
    assert has_element?(view, "#compose-trigger-journal")
    assert length(entries()) == count + 1, "store: #{inspect(stored())}"

    # Reopening and resubmitting the identical payload inside the debounce
    # window writes nothing a second time.
    view |> element("#compose-trigger-journal") |> render_click()
    view |> element("#posting-form") |> render_submit(payload)
    assert length(entries()) == count + 1, "store: #{inspect(stored())}"
  end

  test "a reply without a body is never published" do
    {:ok, view, _html} = live(build_conn(), "/")

    # Seed an entry to answer: publishing one lands us on it, which is what
    # puts the reply trigger on screen.
    view |> element("#compose-trigger-journal") |> render_click()

    view
    |> element("#posting-form")
    |> render_submit(%{"log_id" => "360360", "title" => "Seed", "body" => "seed"})

    assert has_element?(view, "#compose-trigger-reply")
    view |> element("#compose-trigger-reply") |> render_click()
    assert has_element?(view, "#posting-form")

    count = length(entries())

    # Whitespace is still an empty body, and the title is prefilled from the
    # entry being answered — neither is a reply of its own. It is what an
    # accidental Enter in the title field publishes.
    view |> element("#posting-form") |> render_submit(%{"log_id" => "533", "body" => "   "})
    assert length(entries()) == count, "store: #{inspect(stored())}"

    # A body of its own publishes.
    view |> element("#posting-form") |> render_submit(%{"log_id" => "533", "body" => "here"})
    assert length(entries()) == count + 1, "store: #{inspect(stored())}"
  end

  test "only a repeat of the same payload inside the window is a double-click" do
    payload = %{"log_id" => "360360", "title" => "One", "body" => "first body"}
    last = {:erlang.phash2(payload), 1_000}

    assert CatenaryWeb.Live.repeat_publish?(last, payload, 2_999, 2_000)

    refute CatenaryWeb.Live.repeat_publish?(last, payload, 3_000, 2_000)
    refute CatenaryWeb.Live.repeat_publish?(last, %{payload | "body" => "other"}, 1_001, 2_000)
    refute CatenaryWeb.Live.repeat_publish?(nil, payload, 1_001, 2_000)
  end
end
