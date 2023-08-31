defmodule Catenary.IndexWorker.Common do
  def extract_opts(opts) do
    name_atom = Keyword.get(opts, :name_atom)
    name_string = Atom.to_string(name_atom)
    {running, idle} = Keyword.get(opts, :indica)
    extra_tables = Keyword.get(opts, :extra_tables, [])
    {name_atom, name_string, running, idle, extra_tables}
  end

  defmacro __using__(opts) do
    {na, ns, run, idle, et} = extract_opts(opts)
    empty = [na] ++ et

    quote do
      use GenServer
      require Logger
      alias Catenary.{Preferences, Indices}

      def start_link(state) do
        GenServer.start_link(__MODULE__, state, name: unquote(na))
      end

      ## Callbacks

      @impl true
      def init(_arg) do
        Indices.empty_tables(unquote(empty))
        me = self()
        {:ok, %{running: deferred_update_task(%{me: me}), me: me, queued: false}}
      end

      @impl true
      def handle_info({:completed, pid}, state) do
        ns =
          case state do
            %{running: {:ok, ^pid}, queued: true} ->
              %{state | running: deferred_update_task(state), queued: false}

            %{running: {:ok, ^pid}, queued: false} ->
              %{state | running: :idle}

            lump ->
              Logger.debug(unquote(ns) <> " process mismatch")
              IO.inspect({pid, lump})
              %{state | running: :idle}
          end

        Phoenix.PubSub.local_broadcast(Catenary.PubSub, "ui", "index-change")
        {:noreply, ns}
      end

      @impl true
      def handle_call({:update, _args}, _them, %{running: runstate, me: me} = state) do
        case runstate do
          :idle ->
            running = Task.start(fn -> update_from_logs([me]) end)
            Phoenix.PubSub.local_broadcast(Catenary.PubSub, "ui", "index-change")
            {:reply, :started, %{state | running: running, queued: false}}

          {:ok, _pid} ->
            {:reply, :queued, %{state | queued: true}}
        end
      end

      @impl true
      def handle_call(:status, _, %{running: {:ok, _}} = state), do: {:reply, unquote(run), state}
      def handle_call(:status, _, %{running: :idle} = state), do: {:reply, unquote(idle), state}

      defp run_complete([], _), do: :ok

      defp run_complete([pid | rest], which) do
        Process.send(pid, {:completed, which}, [])
        run_complete(rest, which)
      end

      defp deferred_update_task(state) do
        Task.start(fn ->
          Process.sleep(101 + :rand.uniform(1009))
          update_from_logs([state.me])
        end)
      end
    end
  end
end
