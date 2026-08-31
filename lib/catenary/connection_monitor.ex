defmodule Catenary.ConnectionMonitor do
  @moduledoc """
  Watches the live set of `Baby.Connection.Registry` connections and broadcasts
  `:connections_changed` on the `"ui"` topic whenever it changes.

  Connection state in the UI (the Oasis Explorer connected indicators and the
  Manual Connect entries) is otherwise only refreshed as a side effect of
  unrelated `state_set` calls, so it goes stale while the user sits idle. This
  monitor gives the UI near-realtime connect/disconnect notifications: it diffs
  the registry on a short interval and only broadcasts when the active set
  actually changes, so a dropped peer (idle timeout, disconnect) is reflected
  immediately.
  """
  use GenServer

  alias Baby.Connection.Registry

  @check_interval 1_000

  def start_link(_args), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(state) do
    Process.send_after(self(), :check, @check_interval)
    {:ok, Map.put_new(state, :last, nil)}
  end

  @impl true
  def handle_info(:check, %{last: last} = state) do
    current = active_connections()

    if current != last do
      Phoenix.PubSub.local_broadcast(Catenary.PubSub, "ui", :connections_changed)
    end

    Process.send_after(self(), :check, @check_interval)
    {:noreply, %{state | last: current}}
  end

  # The registry lives under Baby.Application, which is started just before us;
  # guard anyway so a transient downbeat of the registry cannot crash the
  # monitor loop.
  defp active_connections do
    if Process.whereis(:conn_reg) do
      Registry.active()
    else
      []
    end
  end
end
