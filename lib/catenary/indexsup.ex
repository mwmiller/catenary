defmodule Catenary.IndexSup do
  use Supervisor

  alias Catenary.IndexWorker.{
    Status,
    Graph,
    Images,
    Tags,
    Mentions,
    Aliases,
    Reactions,
    References,
    Timelines,
    About,
    Oases
  }

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    # These indices are in conversion order.  Feel free to rearrange
    children = [
      Status,
      Graph,
      Images,
      Tags,
      Mentions,
      Aliases,
      Reactions,
      References,
      Timelines,
      About,
      Oases
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
