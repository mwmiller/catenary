defmodule CatenaryWeb.SmokeTest do
  use CatenaryWeb.ConnCase, async: false

  test "GET / boots the LiveView inside the live layout" do
    conn = get(build_conn(), "/")
    assert html_response(conn, 200) =~ "menu-bridge"
  end
end
