defmodule Catenary.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      CatenaryWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Catenary.PubSub},
      # Start the Endpoint (http/https)
      CatenaryWeb.Endpoint,
      # Start a worker by calling: Catenary.Worker.start_link(arg)
      # {Catenary.Worker, arg}
      {Desktop.Window,
       [
         app: :catenary,
         title: "Catenary",
         size: {1117, 661},
         id: CatenaryWindow,
         url: &CatenaryWeb.Endpoint.url/0
       ]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Catenary.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CatenaryWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
