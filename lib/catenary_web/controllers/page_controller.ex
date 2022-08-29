defmodule CatenaryWeb.PageController do
  use CatenaryWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
