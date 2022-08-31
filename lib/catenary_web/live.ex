defmodule CatenaryWeb.Live do
  use CatenaryWeb, :live_view

  # Every 11s or so, we see if someone put new stuff in the store
  @store_refresh 11131

  def mount(_params, _session, socket) do
    # Making sure these exist, but also faux docs
    {:asc, :desc, :author, :logid, :seq}
    Phoenix.PubSub.subscribe(Catenary.PubSub, "iconset")

    default_sort = [dir: :desc, by: :seq]
    default_icons = :png

    Process.send_after(self(), :check_store, @store_refresh, [])

    {:ok, state_set(default_sort, assign(socket, iconset: default_icons))}
  end

  def render(assigns) do
    ~L"""
    <section class="phx-hero" id="page-live">
    <div class="mx-2 grid grid-cols-1 md:grid-cols-2 gap-10 justify-center font-mono">
      <%= live_component(Catenary.Live.OasisBox, id: :recents, watering: @watering, iconset: @iconset) %>
      <%= live_component(Catenary.Live.Browse, id: :browse, store: @store, iconset: @iconset) %>
    </div>
    """
  end

  def handle_info(%{icons: which}, socket) do
    {:noreply, assign(socket, iconset: which)}
  end

  def handle_event("sort", %{"value" => ordering}, socket) do
    [dir, by] = String.split(ordering, "-")

    {:noreply,
     state_set([dir: String.to_existing_atom(dir), by: String.to_existing_atom(by)], socket)}
  end

  def handle_info(:check_store, socket) do
    Process.send_after(self(), :check_store, @store_refresh, [])
    {:noreply, state_set(socket)}
  end

  defp state_set(socket), do: state_set(socket.assigns.sorter, socket)

  defp state_set(sorter, socket) do
    si = Baobab.stored_info()
    assign(socket, store: sorted_store(si, sorter), watering: watering(si), sorter: sorter)
  end

  defp watering(store) do
    store
    |> Enum.filter(fn {_, l, _} -> l == 8483 end)
    |> extract_recents(DateTime.now!("Etc/UTC"), [])
  end

  defp extract_recents([], _, acc) do
    # Put them in age order
    # Pick the most recent for any host/port dupes
    # Display a max of 3
    acc
    |> Enum.sort_by(fn m -> Map.get(m, :age) end, :asc)
    |> Enum.uniq_by(fn %{"host" => h, "port" => p} -> {h, p} end)
    |> Enum.take(4)
  end

  defp extract_recents([{a, l, e} | rest], now, acc) do
    try do
      %Baobab.Entry{payload: payload} = Baobab.log_entry(a, e, log_id: l)
      {:ok, map, ""} = CBOR.decode(payload)

      case map do
        %{"running" => ts} ->
          {:ok, then, _offset} = DateTime.from_iso8601(ts)
          sago = DateTime.diff(now, then)

          cond do
            sago > -172_800 ->
              extract_recents(rest, now, [
                Map.merge(map, %{age: sago, id: a}) | acc
              ])

            true ->
              extract_recents(rest, now, acc)
          end

        _ ->
          extract_recents(rest, now, acc)
      end
    rescue
      _ -> extract_recents(rest, now, acc)
    end
  end

  defp sorted_store(store, opts) do
    elem =
      case Keyword.get(opts, :by) do
        :author -> fn {a, _, _} -> a end
        :logid -> fn {_, l, _} -> l end
        :seq -> fn {_, _, s} -> s end
      end

    comp =
      case Keyword.get(opts, :dir) do
        :asc -> &Kernel.<=/2
        :desc -> &Kernel.>=/2
      end

    # The extra step keeps it stable across
    # refresh from stored_info which is in the
    # described order [dir: :asc, by: author]
    # We also filter out Baby annoucement logs because
    # We're using them differently
    # If this ever becomes more than POC and a botleneck, yay!
    store
    |> Enum.reject(fn {_, l, _} -> l == 8483 end)
    |> Enum.sort_by(fn {a, _, _} -> a end, &Kernel.<=/2)
    |> Enum.sort_by(elem, comp)
  end
end
