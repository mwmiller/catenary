defmodule Catenary.IndexWorker.Status do
  @moduledoc """
  Agent-backed status store for catenary's indexing progress.

  Broadcasts `:index_change` on the `"ui"` PubSub topic so the LiveView
  re-renders index-backed components.  To avoid flooding the UI during rapid
  replication cycles the broadcast is throttled:

    * `:idle` — always broadcast (the work is done, the UI should refresh).
    * `:running` — broadcast at most once every 5 seconds, giving periodic
      progress updates during long indexing passes without spam.
  """
  use Agent

  @backoff_ms 5_003

  def start_link(_args) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def get_all do
    Agent.get(__MODULE__, fn state ->
      state
      |> Enum.map(fn {which, entry} -> {which, normalize(entry)} end)
      |> Enum.sort()
    end)
  end

  # Legacy values stored before set/3 carried the state tuple.
  defp normalize({char, state, _last_broadcast}), do: {char, state}
  defp normalize({char, state}), do: {char, state}
  defp normalize(char), do: {char, :idle}

  # :idle — always broadcast; the indexing pass is complete.
  def set(which, char, :idle = state) do
    now = System.monotonic_time(:millisecond)
    Phoenix.PubSub.local_broadcast(Catenary.PubSub, "ui", :index_change)
    Agent.update(__MODULE__, fn s -> Map.put(s, which, {char, state, now}) end)
  end

  # :running — broadcast only if at least @backoff_ms have elapsed since the
  # last broadcast for this worker, giving the UI periodic progress updates
  # during long passes without flooding during rapid replication cycles.
  def set(which, char, state) do
    now = System.monotonic_time(:millisecond)

    Agent.update(__MODULE__, fn s ->
      last_broadcast =
        case Map.get(s, which) do
          {_, _, lb} -> lb
          _ -> 0
        end

      if now - last_broadcast >= @backoff_ms do
        Phoenix.PubSub.local_broadcast(Catenary.PubSub, "ui", :index_change)
        Map.put(s, which, {char, state, now})
      else
        Map.put(s, which, {char, state, last_broadcast})
      end
    end)
  end
end
