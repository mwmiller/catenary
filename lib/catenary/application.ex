defmodule Catenary.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  alias Catenary.Preferences

  require Logger

  use Application

  @impl true
  def start(_type, _args) do
    # Still bad form
    Application.put_env(:baobab, :spool_dir, spool_dir())

    whoami = active_identity()

    clumps =
      for {c, k} <- Application.get_env(:catenary, :clumps) do
        [
          controlling_identity: whoami,
          id: c,
          port: Keyword.get(k, :port),
          announce: Keyword.get(k, :announce, false),
          cryouts: Keyword.get(k, :cryouts, [])
        ]
      end

    img_root =
      Path.join([
        Application.get_env(:catenary, :application_dir),
        "images"
      ])
      |> Path.expand()

    File.mkdir_p(Path.join([img_root, "identicons"]))

    children = [
      {Baby.Application, spool_dir: spool_dir(), clumps: clumps},
      # Start the Telemetry supervisor
      CatenaryWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Catenary.PubSub},
      # Pushes near-realtime connect/disconnect changes to the web UI
      Catenary.ConnectionMonitor,
      # Start the Endpoint (http/https)
      CatenaryWeb.Endpoint,
      Catenary.IndexSup,
      Catenary.State
    ]

    opts = [strategy: :one_for_one, name: Catenary.Supervisor]
    {:ok, sup} = Supervisor.start_link(children, opts)

    # Baobab's Log.Acceptor populates :status dets asynchronously, so the
    # index workers' initial loads can run against a cold store. Force a
    # re-index once it has had a chance to load so workers (e.g. :oases)
    # rebuild from the populated store rather than staying empty.
    Task.start(fn ->
      Process.sleep(3000)
      Catenary.Indices.force_update()
    end)

    {:ok, sup}
  end

  # Resolve the recorded identity to its stored name. When the identity
  # store has lost the keys we prefer an honest nil (plus a loud log) over
  # fabricating or auto-creating a replacement identity.
  defp active_identity do
    case Preferences.get(:identity) |> Catenary.id_for_key() do
      {:error, msg} ->
        Logger.error("Unresolvable controlling identity: #{msg}")
        nil

      name ->
        name
    end
  end

  def spool_dir do
    # Ensure the application directory exists
    app_dir = Catenary.home_dir()

    # Including the spool directory
    spool_dir = Path.join(app_dir, "spool")
    File.mkdir_p(spool_dir)
    spool_dir
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CatenaryWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
