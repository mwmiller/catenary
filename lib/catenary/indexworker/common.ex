defmodule Catenary.IndexWorker.Common do
  @moduledoc """
  Common.__using__/1 setup shared by all index worker GenServers: table names, the :logs_of_interest module attribute, start_link, and index/init plumbing.
  """
  def extract_opts(opts) do
    name_atom = Keyword.get(opts, :name_atom)
    {running, idle} = Keyword.get(opts, :indica)
    loi = Keyword.get(opts, :logs)
    extra_tables = Keyword.get(opts, :extra_tables, [])
    {name_atom, running, idle, extra_tables, loi}
  end

  defmacro __using__(opts) do
    {na, run, idle, et, loi} = extract_opts(opts)
    empty = [na] ++ et

    quote do
      use GenServer
      alias Catenary.IndexWorker.Status
      alias Catenary.Indices
      alias Catenary.Preferences

      @logs_of_interest unquote(loi)

      def start_link(state) do
        GenServer.start_link(__MODULE__, state, name: unquote(na))
      end

      ## Callbacks

      @impl true
      def init(_arg) do
        Indices.empty_tables(unquote(empty))

        {:ok, %{indexed: %{}}, {:continue, :load}}
      end

      @impl true
      def handle_continue(:load, state) do
        update_from_logs(state)
      end

      def update_from_logs(%{indexed: seen} = state) do
        Status.set(unquote(na), unquote(run), :running)
        clump_id = Preferences.get(:clump_id)
        current = clump_id |> Baobab.stored_info()

        {mapped_curr, todo} = updated_logs(current, seen, {%{}, []})
        game_seen = do_index(todo, clump_id, seen)

        Status.set(unquote(na), unquote(idle), :idle)
        {:noreply, %{state | indexed: Map.merge(mapped_curr, game_seen)}}
      end

      defp run_update(%{indexed: seen} = state) do
        Status.set(unquote(na), unquote(run), :running)
        clump_id = Preferences.get(:clump_id)
        current = clump_id |> Baobab.stored_info()

        {mapped_curr, todo} = updated_logs(current, seen, {%{}, []})
        game_seen = do_index(todo, clump_id, seen)

        Status.set(unquote(na), unquote(idle), :idle)
        %{state | indexed: Map.merge(mapped_curr, game_seen)}
      end

      def force_rebuild(state) do
        Status.set(unquote(na), unquote(run), :running)
        clump_id = Preferences.get(:clump_id)
        current = clump_id |> Baobab.stored_info()

        {mapped_curr, todo} = updated_logs(current, %{}, {%{}, []})
        game_seen = do_index(todo, clump_id, %{})

        Status.set(unquote(na), unquote(idle), :idle)
        {:noreply, %{state | indexed: Map.merge(mapped_curr, game_seen)}}
      end

      defp updated_logs([], _, acc), do: acc

      defp updated_logs([{a, l, e} = entry | rest], seen, {mc, td}) when l in @logs_of_interest do
        key = {a, l}

        ntd =
          case Map.get(seen, key) do
            ^e -> td
            _ -> [entry | td]
          end

        updated_logs(rest, seen, {Map.put(mc, key, e), ntd})
      end

      defp updated_logs([_ | rest], seen, acc), do: updated_logs(rest, seen, acc)

      @impl true
      def handle_cast(:update, state), do: {:noreply, run_update(state)}

      @impl true
      def handle_call(:update, _from, state), do: {:reply, :ok, run_update(state)}

      @impl true
      def handle_cast(:force_rebuild, state) do
        wipe_for_rebuild()
        force_rebuild(state)
      end

      # How a manual reindex clears the local table before the full log pass
      # refills it. Workers that rebuild in place override this with :ok and
      # prune their own stale rows once the pass completes.
      def wipe_for_rebuild, do: Indices.empty_tables(unquote(empty))

      # Default: no-op. Workers override to do their indexing work and return
      # a map of keys to track for incremental fold caching (currently only
      # the challenges worker returns a non-empty map).
      def do_index(_todo, _clump_id, prev_seen), do: prev_seen

      defoverridable force_rebuild: 1, wipe_for_rebuild: 0, do_index: 3
    end
  end
end
