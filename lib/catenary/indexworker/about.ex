defmodule Catenary.IndexWorker.About do
  use GenServer
  alias Catenary.Preferences
  require Logger

  @moduledoc """
  About Indices
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
        Logger.debug("tags queued happypath")

        {:ok, running} =
          Task.start(fn ->
            Process.sleep(2017)
            update_from_logs(state.me)
          end)

        {:noreply, %{state | running: running}}

      %{running: {:ok, ^pid}, queued: false} ->
        Logger.debug("about clear happypath")
        {:noreply, %{state | running: :idle}}

      lump ->
        Logger.debug("about process mismatch")
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
  def handle_call(:status, _, %{running: {:ok, _}} = _state), do: "⧞"
  def handle_call(:status, _, %{running: :idle} = _state), do: "∞"

  def update_from_logs(inform \\ nil) do
    clump_id = Preferences.get(:clump_id)
    logs = QuaggaDef.logs_for_name(:about)

    clump_id
    |> Baobab.stored_info()
    |> Enum.reduce([], fn {a, l, _}, acc ->
      case l in logs do
        false -> acc
        true -> [{a, l} | acc]
      end
    end)
    |> gather_updates(clump_id, %{})
    |> Map.to_list()
    |> build_index(clump_id)

    case inform do
      nil -> :ok
      pid -> Process.send(pid, {:completed, self()}, [])
    end
  end

  defp gather_updates([], _, acc), do: acc

  defp gather_updates([{who, log_id} | rest], clump_id, acc) do
    gather_updates(
      rest,
      clump_id,
      acc
      |> Map.put_new(who, [])
      |> Map.update!(who, fn extant ->
        extant ++ process_entries(Baobab.full_log(who, log_id: log_id, clump_id: clump_id), [])
      end)
    )
  end

  defp process_entries([], acc), do: acc

  defp process_entries([curr | rest], acc) do
    try do
      %Baobab.Entry{payload: payload} = curr
      {:ok, data, ""} = CBOR.decode(payload)
      process_entries(rest, [{data["published"], data} | acc])
    rescue
      _ -> process_entries(rest, acc)
    end
  end

  defp build_index([], _cid), do: :ok

  defp build_index([{ident, updates} | rest], clump_id) do
    final_form =
      updates
      |> Enum.sort()
      |> Enum.reduce(%{}, fn {_when, what}, acc -> Map.merge(acc, what) end)

    case final_form do
      %{"avatar" => [a, l, e]} ->
        :ets.insert(:avatars, {ident, {a, l, e, clump_id}})

      _ ->
        :ok
    end

    :ets.insert(:about, {ident, final_form})
    build_index(rest, clump_id)
  end
end
