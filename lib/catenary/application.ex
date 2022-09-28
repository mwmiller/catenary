defmodule Catenary.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  require Catenary.MenuMaker

  use Application

  @impl true
  def start(_type, _args) do
    # Ensure the application directory exists
    app_dir =
      :catenary
      |> Application.get_env(:application_dir, "~/.catenary")
      |> Path.expand()

    # Including the spool directory
    spool_dir = Path.join(app_dir, "spool")
    File.mkdir_p(spool_dir)

    whoami = Catenary.Preferences.get(:identity)
    clump_id = Catenary.Preferences.get(:clump_id)

    # I need a better signal for when to do this
    # but the store is mutable by others
    # slower start up tradeoff for now
    Catenary.Indices.clear_all()

    children = [
      {Baby.Application, [spool_dir: spool_dir, identity: whoami, clump_id: clump_id]},
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
         menubar: prepare_menubar("MenuBar", menu_structure()),
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

  def prepare_menubar(name, structure) do
    full_name = Module.concat("Catenary", name)
    Catenary.MenuMaker.generate(full_name, structure)

    case Code.ensure_compiled(full_name) do
      {:module, module} -> module
      {:error, why} -> raise(why)
    end
  end

  defp menu_structure do
    [
      {"File",
       [
         %{label: "Open dashboard", command: "dashboard", action: %{view: :dashboard}},
         %{label: "Manage identities", command: "idents", action: %{view: :idents}},
         %{label: "Quit", command: "quit"}
       ]},
      {"Explore",
       [
         %{label: "Tags", command: "tag", action: %{tag: :all}},
         %{label: "Journals", command: "journal", action: %{entry: :journal}},
         %{label: "Replies", command: "reply", action: %{entry: :reply}},
         %{label: "Aliases", command: "alias", action: %{entry: :alias}},
         %{label: "Oases", command: "oasis", action: %{entry: :oasis}},
         %{label: "Test posts", command: "test", action: %{entry: :test}}
       ]}
    ]
  end
end
