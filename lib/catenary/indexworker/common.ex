defmodule Catenary.IndexWorker.Common do
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
      require Logger
      alias Catenary.{Preferences, Indices}
      alias Catenary.IndexWorker.Status

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
        Status.set(unquote(na), unquote(run))
        clump_id = Preferences.get(:clump_id)
        current = clump_id |> Baobab.stored_info()

        {mapped_curr, todo} = updated_logs(current, seen, {%{}, []})
        do_index(todo, clump_id)

        Status.set(unquote(na), unquote(idle))
        {:noreply, %{state | indexed: mapped_curr}}
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
      def handle_cast(:update, state), do: update_from_logs(state)
    end
  end
end
