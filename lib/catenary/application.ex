defmodule Catenary.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  alias Catenary.Preferences
  require Catenary.MenuMaker

  use Application

  @impl true
  def start(_type, _args) do
    # Still bad form
    Application.put_env(:baobab, :spool_dir, spool_dir())

    whoami = Preferences.get(:identity) |> Catenary.id_for_key()

    clumps =
      for {c, k} <- Application.get_env(:catenary, :clumps) do
        [controlling_identity: whoami, id: c, port: Keyword.get(k, :port)]
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

    winsize = Preferences.get(:winsize)

    children = [
      {Baby.Application, spool_dir: spool_dir(), clumps: clumps},
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
         size: winsize,
         id: CatenaryWindow,
         menubar: prepare_menubar("MenuBar", menu_structure()),
         url: &CatenaryWeb.Endpoint.url/0
       ]},
      Catenary.IndexSup,
      Catenary.State
    ]

    opts = [strategy: :one_for_one, name: Catenary.Supervisor]
    Supervisor.start_link(children, opts)
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
         %{label: "Dashboard", command: "dashboard", action: %{view: :dashboard, entry: :none}},
         %{label: "Preferences...", command: "prefs", action: %{view: :prefs, entry: :none}},
         :rule,
         %{label: "Reset view", command: "reset"},
         :rule,
         %{label: "Quit", command: "quit"}
       ]},
      {"Explore",
       [
         %{label: "Unshown", command: "unshown", action: %{view: :unshown, entry: :all}},
         %{label: "Tags", command: "tag", action: %{view: :tags, entry: :all}},
         %{label: "Aliases", command: "alias", action: %{view: :aliases, entry: :all}},
         %{label: "Images", command: "image", action: %{view: :images, entry: :all}},
         :rule,
         %{label: "Journals", command: "journal", action: %{view: :entries, entry: :journal}},
         %{label: "Replies", command: "reply", action: %{view: :entries, entry: :reply}},
         %{label: "Reactions", command: "react", action: %{view: :entries, entry: :react}},
         %{label: "Mentions", command: "mention", action: %{view: :entries, entry: :mention}},
         :rule,
         %{label: "Test posts", command: "test", action: %{view: :entries, entry: :test}},
         :rule,
         %{label: "Oases", command: "oasis", action: %{view: :entries, entry: :oasis}}
       ]}
    ]
  end
end
