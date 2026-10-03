defmodule CatenaryWeb.Router do
  use CatenaryWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {CatenaryWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # A pane fetching its module asks for bytes, not a document: wasm for
  # the fetch, html if the route is opened directly.
  pipeline :module do
    plug :accepts, ["wasm", "html"]
  end

  scope "/", CatenaryWeb do
    pipe_through :browser

    live("/", Live)
    get "/entries/:index_format", EntryController, :view
    get "/entries/:identity/:log_id/:seqnum", EntryController, :view
    get "/authors/:identity", ProfileController, :view
    post "/export", ExportController, :create
    get "/export", ExportController, :create
    get "/export/clumps", ExportController, :clumps
    post "/import", ImportController, :create
  end

  scope "/", CatenaryWeb do
    pipe_through :module

    get "/apps/:pk/:slug/module", AppController, :module
  end

  # Other scopes may use custom stacks.
  # scope "/api", CatenaryWeb do
  #   pipe_through :api
  # end

  import Phoenix.LiveDashboard.Router

  scope "/" do
    pipe_through :browser

    live_dashboard "/dashboard",
      metrics: CatenaryWeb.Telemetry,
      on_mount: CatenaryWeb.LiveDashboardHooks
  end
end
