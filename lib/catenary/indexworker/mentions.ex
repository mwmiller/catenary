defmodule Catenary.IndexWorker.Mentions do
  use GenServer
  alias Catenary.{Preferences, Indices}
  require Logger

  @moduledoc """
  Mention Indices
  """

  @name_atom :mentions

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
        Logger.debug("mentions queued happypath")

        running =
          Task.start(fn ->
            Process.sleep(2017)
            update_from_logs(state.me)
          end)

        {:noreply, %{state | running: running, queued: false}}

      %{running: {:ok, ^pid}, queued: false} ->
        Logger.debug("mentions clear happypath")
        {:noreply, %{state | running: :idle}}

      lump ->
        Logger.debug("mentions process mismatch")
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
  def handle_call(:status, _, %{running: {:ok, _}} = state), do: {:reply, "⎒", state}
  def handle_call(:status, _, %{running: :idle} = state), do: {:reply, "⎑", state}

  def update_from_logs(inform \\ nil) do
    clump_id = Preferences.get(:clump_id)

    logs =
      :mention
      |> QuaggaDef.logs_for_name()

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
    # This is a two-way index
    try do
      %Baobab.Entry{payload: payload} = entry
      {:ok, data, ""} = CBOR.decode(payload)
      mentions = data["mentions"] |> Enum.map(fn s -> {"", String.trim(s)} end)
      [ent] = data["references"]
      e = List.to_tuple(ent)
      # Mentions for entry
      old =
        case :ets.lookup(@name_atom, e) do
          [] -> []
          [{^e, val}] -> val
        end

      into = (old ++ mentions) |> Enum.sort() |> Enum.uniq()
      :ets.insert(@name_atom, {e, into})

      # Entries for mentioned
      for mention <- mentions do
        old_val =
          case :ets.lookup(@name_atom, mention) do
            [] -> []
            [{^mention, val}] -> val
          end

        insert =
          [{Indices.published_date(data), e} | old_val]
          |> Enum.sort()
          |> Enum.uniq_by(fn {_p, e} -> e end)

        :ets.insert(@name_atom, {mention, insert})
      end
    rescue
      _ -> :ok
    end

    entries_index(rest, clump_id)
  end
end
