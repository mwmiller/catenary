defmodule Catenary.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  alias Catenary.Preferences

  use Application

  @impl true
  def start(_type, _args) do
    # Still bad form
    Application.put_env(:baobab, :spool_dir, spool_dir())

    whoami = Preferences.get(:identity) |> Catenary.id_for_key()

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

    local_root =
      Path.join([Application.app_dir(:catenary), "priv/static/cat_images"])
      |> Path.expand()

    case File.read_link(local_root) do
      {:ok, ^img_root} ->
        :ok

      _ ->
        File.rm_rf(local_root)
        File.ln_s(img_root, local_root)
    end

    File.mkdir_p(Path.join([img_root, "identicons"]))

    children = [
      {Baby.Application, spool_dir: spool_dir(), clumps: clumps},
      # Start the Telemetry supervisor
      CatenaryWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Catenary.PubSub},
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

  def spool_dir do
    # Ensure the application directory exists
    app_dir =
      :catenary
      |> Application.get_env(:application_dir, "~/.catenary")
      |> Path.expand()

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
