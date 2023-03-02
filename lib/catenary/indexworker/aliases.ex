defmodule Catenary.IndexWorker.Aliases do
  use GenServer
  alias Catenary.{Preferences, Indices}
  require Logger

  @moduledoc """
  Alias Indices
  """

  @name_atom :aliases

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: @name_atom)
  end

  ## Callbacks

  @impl true
  def init(_arg) do
    Indices.empty_table(@name_atom)
    me = self()
    running = Task.start(fn -> update_from_logs(me) end)

    {:ok, %{running: running, me: me, queued: false}}
  end

  @impl true
  def handle_info({:completed, pid}, state) do
    case state do
      %{running: {:ok, ^pid}, queued: true} ->
        Logger.debug("aliases queued happypath")

        running =
          Task.start(fn ->
            Process.sleep(2017)
            update_from_logs(state.me)
          end)

        {:noreply, %{state | running: running, queued: false}}

      %{running: {:ok, ^pid}, queued: false} ->
        Logger.debug("aliases clear happypath")
        {:noreply, %{state | running: :idle}}

      lump ->
        Logger.debug("aliases process mismatch")
        IO.inspect({pid, lump})
        {:noreply, %{state | running: :idle}}
    end
  end

  @impl true
  def handle_call({:update, _args}, _them, %{running: runstate} = state) do
    case runstate do
      :idle ->
        running = Task.start(fn -> update_from_logs(self()) end)
        {:reply, :started, %{state | running: running, queued: false}}

      {:ok, _pid} ->
        {:reply, :queued, %{state | queued: true}}
    end
  end

  @impl true
  def handle_call(:status, _, %{running: {:ok, _}} = state), do: {:reply, "⍲", state}
  def handle_call(:status, _, %{running: :idle} = state), do: {:reply, "⍱", state}

  def update_from_logs(inform \\ nil) do
    {identity, clump_id} = {Preferences.get(:identity), Preferences.get(:clump_id)}

    logs =
      :alias
      |> QuaggaDef.logs_for_name()

    clump_id
    |> Baobab.stored_info()
    |> Enum.reduce([], fn {a, l, _}, acc ->
      case a == identity and l in logs do
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
      %Baobab.Entry{payload: payload} = entry
      {:ok, data, ""} = CBOR.decode(payload)
      :ets.match_delete(@name_atom, {:_, data["alias"]})
      :ets.insert(@name_atom, {data["whom"], data["alias"]})
    rescue
      _ ->
        :ok
    end

    entries_index(rest, clump_id)
  end
end
