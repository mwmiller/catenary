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
    assert back =~ "px-2 py-1 rounded"
    assert Regex.scan(~r/class="/, fwd) |> length() == 1
    assert fwd =~ "px-2 py-1 rounded"
  end
end
