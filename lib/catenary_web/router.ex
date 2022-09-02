defmodule CatenaryWeb.Router do
  use CatenaryWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {CatenaryWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", CatenaryWeb do
    pipe_through :browser

    live("/", Live)
  end

  # Other scopes may use custom stacks.
  # scope "/api", CatenaryWeb do
  #   pipe_through :api
  # end

  import Phoenix.LiveDashboard.Router

  scope "/" do
    pipe_through :browser
    live_dashboard "/dashboard", metrics: CatenaryWeb.Telemetry
  end
end
