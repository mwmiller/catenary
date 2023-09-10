defmodule Catenary.IndexWorker.Status do
  use Agent

  def start_link(_args) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def get_all do
    # I believe this is ordered as long as I have fewer than 32 entries
    # I should look it up, but I am weak.
    Agent.get(__MODULE__, fn state -> state |> Map.values() end)
  end

  def set(which, value) do
    Phoenix.PubSub.local_broadcast(Catenary.PubSub, "ui", :index_change)

    case value do
      :idle -> Agent.update(__MODULE__, fn state -> Map.drop(state, [which]) end)
      char -> Agent.update(__MODULE__, fn state -> Map.put(state, which, char) end)
    end
  end
end
