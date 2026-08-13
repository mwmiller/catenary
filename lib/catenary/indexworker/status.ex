defmodule Catenary.IndexWorker.Status do
  @moduledoc """
  Agent-backed status store for catenary's indexing progress.
  """
  use Agent

  def start_link(_args) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def get_all do
    # I believe this is ordered as long as I have fewer than 32 entries
    # I should look it up, but I am weak.
    Agent.get(__MODULE__, fn state ->
      state
      |> Enum.map(fn {which, value} -> {which, normalize(value)} end)
      |> Enum.sort()
    end)
  end

  # Legacy values stored before set/3 carried the state tuple.
  defp normalize({char, state}), do: {char, state}
  defp normalize(char), do: {char, :idle}

  def set(which, char, state) do
    Phoenix.PubSub.local_broadcast(Catenary.PubSub, "ui", :index_change)
    Agent.update(__MODULE__, fn s -> Map.put(s, which, {char, state}) end)
  end
end
