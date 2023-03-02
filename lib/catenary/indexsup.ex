defmodule Catenary.IndexSup do
  use Supervisor
  alias Catenary.IndexWorker.{Images, SocialGraph, Tags, Mentions}

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [SocialGraph, Images, Tags, Mentions]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
