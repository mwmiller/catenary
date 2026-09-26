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

    # The test clump has no entries, so the "you have unread entries" highlight
    # must not be applied. This also pins that state_set/3 still assigns
    # has_unshown at all: the button below is its only consumer, and a missing
    # assign would raise while rendering it.
    refute unshown =~ "text-amber-600"
    assert unshown =~ "btn-icon"
  end
end
