defmodule Catenary.IndexWorker.Timelines do
  use GenServer
  alias Catenary.Preferences
  require Logger

  @moduledoc """
  Timeline Indices
  """

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  ## Callbacks

  @impl true
  def init(_arg) do
    me = self()
    {:ok, running} = Task.start(fn -> update_from_logs(me) end)

    {:ok, %{running: {:ok, running}, me: me, queued: false}}
  end

  @impl true
  def handle_info({:completed, pid}, state) do
    case state do
      %{running: {:ok, ^pid}, queued: true} ->
        Logger.debug("timelines queued happypath")

        {:ok, running} =
          Task.start(fn ->
            Process.sleep(2017)
            update_from_logs(state.me)
          end)

        {:noreply, %{state | running: running}}

      %{running: {:ok, ^pid}, queued: false} ->
        Logger.debug("timelines clear happypath")
        {:noreply, %{state | running: :idle}}

      lump ->
        Logger.debug("timelines process mismatch")
        IO.inspect({pid, lump})
        {:noreply, %{state | running: :idle}}
    end
  end

  @impl true
  def handle_cast({:update, _args}, %{running: runstate} = state) do
    case runstate do
      :idle ->
        {:ok, running} = Task.start(fn -> update_from_logs(self()) end)
        {:noreply, %{state | running: running, queued: false}}

      {:ok, _pid} ->
        {:noreply, %{state | queued: true}}
    end
  end

  @impl true
  def handle_call(:status, _, %{running: {:ok, _}} = _state), do: "⫝̸"
  def handle_call(:status, _, %{running: :idle} = _state), do: "⫝"

  def update_from_logs(inform \\ nil) do
    clump_id = Preferences.get(:clump_id)

    logs =
      Enum.reduce(Catenary.timeline_logs(), [], fn n, a -> a ++ QuaggaDef.logs_for_name(n) end)

    clump_id
    |> Baobab.stored_info()
    |> Enum.reduce([], fn {a, l, _}, acc ->
      case l in logs do
        true -> [{a, l} | acc]
        false -> acc
      end
    end)
    |> build_index(clump_id)

    case inform do
      nil -> :ok
      pid -> Process.send(pid, {:completed, self()}, [])
    end
  end

  defp build_index([], _), do: :ok

  defp build_index([{a, l} | rest], clump_id) do
    entries_index(Baobab.full_log(a, log_id: l, clump_id: clump_id), clump_id)
    build_index(rest, clump_id)
  end

  # This could maybe give up on a CBOR failure, eventually
  # Right now we have a lot of mixed types
  defp entries_index([], _), do: :ok

  defp entries_index([entry | rest], clump_id) do
    try do
      %Baobab.Entry{author: a, log_id: l, seqnum: s, payload: payload} = entry
      ident = Baobab.Identity.as_base62(a)
      {:ok, data, ""} = CBOR.decode(payload)

      old =
        case :ets.lookup(:timelines, ident) do
          [] -> []
          [{^ident, val}] -> val
        end

      insert = [{published(data), {ident, l, s}} | old] |> Enum.sort() |> Enum.uniq()

      :ets.insert(:timelines, {ident, insert})
    rescue
      _ -> :ok
    end

    entries_index(rest, clump_id)
  end

  defp published(data) when is_map(data) do
    case data["published"] do
      nil ->
        ""

      t ->
        t
        |> Timex.parse!("{ISO:Extended}")
        |> Timex.to_unix()
    end
  end

  defp published(_), do: ""
end
