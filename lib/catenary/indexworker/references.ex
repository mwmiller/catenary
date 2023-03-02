defmodule Catenary.IndexWorker.References do
  use GenServer
  alias Catenary.Preferences
  require Logger

  @moduledoc """
  Tag Indices
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
        Logger.debug("references queued happypath")

        {:ok, running} =
          Task.start(fn ->
            Process.sleep(2017)
            update_from_logs(state.me)
          end)

        {:noreply, %{state | running: running}}

      %{running: {:ok, ^pid}, queued: false} ->
        Logger.debug("references clear happypath")
        {:noreply, %{state | running: :idle}}

      lump ->
        Logger.debug("references process mismatch")
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
  def handle_call(:status, _, %{running: {:ok, _}} = _state), do: "🜪"
  def handle_call(:status, _, %{running: :idle} = _state), do: "🜚"

  def update_from_logs(inform \\ nil) do
    clump_id = Preferences.get(:clump_id)

    logs =
      :cbor
      |> QuaggaDef.logs_for_encoding()

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
      index = {Baobab.Identity.as_base62(a), l, s}
      {:ok, data, ""} = CBOR.decode(payload)

      for lref <- Map.get(data, "references") do
        tref = lref |> List.to_tuple()

        old_val =
          case :ets.lookup(:references, tref) do
            [] -> []
            [{^tref, val}] -> val
          end

        new_val = (old_val ++ [{published(data), index}]) |> Enum.sort() |> Enum.uniq()

        :ets.insert(:references, {tref, new_val})
      end
    rescue
      _ ->
        :ok
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
