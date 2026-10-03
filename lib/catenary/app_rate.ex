defmodule Catenary.AppRate do
  @moduledoc """
  The call budget every app spends its host operations from.

  Amplification through the host (§11 risk 6) is bounded in one place
  rather than in each operation: one bucket per app — `{clump_id, pk,
  slug}` — refills every window, and `take/1` spends a token or refuses.
  A refusal is an ordinary host answer (`rate_limited`), so a runaway
  loop strikes itself out — five refusals stop the run — while an app
  doing normal work never notices, because the budget sits far above the
  handful of operations a tick issues. The same budget covers both
  viewers of one app: the limit is on the app's calls, not on who opened
  it.

  The bucket is an ETS counter keyed by window slot, so concurrent wants
  spend atomically, and a periodic sweep drops the slots time has passed:
  an app that stopped running leaves no windows behind.

  `Catenary.AppHost` spends this budget in front of its dispatch — this
  module owns the table, not the door.
  """

  use GenServer

  @table :app_rate

  # One window, one number: how many host calls an app gets inside it.
  # The window is short enough that hitting the ceiling ends a runaway in
  # milliseconds, and wide enough that a burst of work from a legitimate
  # app (open, read, render) has room to land in one window.
  @window_ms 1_000
  @default_burst 60

  # Stale slots are only ever this old when the sweep runs, so one sweep
  # per minute keeps the table at roughly one live slot per running app.
  @sweep_ms 60_000

  @type app :: Catenary.AppHost.app()

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Spend one call from `app`'s bucket: `:ok`, or `{:error, :rate_limited}`
  once this window's budget is gone.

  `:infinity` (the test configuration) never refuses, so a suite that
  hammers one app in a tight loop is never racing a clock.
  """
  @spec take(app) :: :ok | {:error, :rate_limited}
  def take(%{clump_id: c, pk: p, slug: s})
      when is_binary(c) and is_binary(p) and is_binary(s) do
    case burst() do
      :infinity ->
        :ok

      burst when is_integer(burst) and burst > 0 ->
        slot = System.monotonic_time(:millisecond) |> div(@window_ms)
        count = :ets.update_counter(@table, {c, p, s, slot}, {2, 1}, {{c, p, s, slot}, 0})

        if count > burst do
          {:error, :rate_limited}
        else
          :ok
        end
    end
  end

  # `AppHost` validates the app before spending; anything else reaching
  # here is not a spend at all.
  def take(_app), do: :ok

  @doc """
  The current ceiling in force, `:infinity` when limiting is off.
  """
  @spec burst() :: pos_integer | :infinity
  def burst, do: Application.get_env(:catenary, :app_rate_burst, @default_burst)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.monotonic_time(:millisecond) |> div(@window_ms)
    # A slot the clock has passed can never be spent against again — the
    # key carries its window — so every entry under it is dead weight.
    # Slot `now` itself stays: it is the one `take/1` is counting in.
    :ets.select_delete(@table, [{{{:_, :_, :_, :"$1"}, :_}, [{:<, :"$1", now}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_ms)
end
