defmodule Catenary.IndexSup do
  use Supervisor

  alias Catenary.IndexWorker.{
    Graph,
    Images,
    Tags,
    Mentions,
    Aliases,
    Reactions,
    References,
    Timelines,
    About
  }

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    # These indices are in conversion order.  Feel free to rearrange
    children = [
      Graph,
      Images,
      Tags,
      Mentions,
      Aliases,
      Reactions,
      References,
      Timelines,
      About
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
