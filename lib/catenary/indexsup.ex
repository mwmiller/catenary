defmodule Catenary.IndexSup do
  use Supervisor
  alias Catenary.IndexWorker.{SocialGraph, Images, Tags, Mentions, Aliases, Reactions, References}

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [SocialGraph, Images, Tags, Mentions, Aliases, Reactions, References]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
