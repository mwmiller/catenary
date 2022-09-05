defmodule CatenaryWeb.Live do
  use CatenaryWeb, :live_view

  # Every second or so, we see if someone put new stuff in the store
  @ui_refresh 1061

  def mount(_params, _session, socket) do
    # Making sure these exist, but also faux docs
    {:asc, :desc, :author, :logid, :seq}
    Phoenix.PubSub.subscribe(Catenary.PubSub, "ui")

    default_sort = [dir: :desc, by: :seq]
    default_icons = :png

    entry =
      case connected?(socket) do
        true ->
          Process.send_after(self(), :check_store, @ui_refresh, [])
          :random

        false ->
          :none
      end

    {:ok,
     state_set(
       default_sort,
       assign(socket, iconset: default_icons, entry: entry, connections: [])
     )}
  end

  def render(assigns) do
    ~L"""
    <section class="phx-hero" id="page-live">
    <div class="mx-2 grid grid-cols-1 md:grid-cols-2 gap-10 justify-center font-mono">
      <%= live_component(Catenary.Live.OasisBox, id: :recents, connections: @connections, watering: @watering, iconset: @iconset) %>
      <%= live_component(Catenary.Live.Browse, id: :browse, store: Enum.take(@store, 5), iconset: @iconset) %>
      <%= live_component(Catenary.Live.EntryViewer, id: :entry, store: @store, entry: @entry, iconset: @iconset) %>
      <%= live_component(Catenary.Live.Navigation, id: :nav, entry: @entry) %>
    </div>
    """
  end

  def handle_info(%{icons: which}, socket) do
    {:noreply, assign(socket, iconset: which)}
  end

  def handle_info(%{view: :dashboard}, socket) do
    {:noreply, push_redirect(socket, to: Routes.live_dashboard_path(socket, :home))}
  end

  def handle_info(%{entry: which}, socket) do
    {:noreply, assign(socket, entry: which)}
  end

  def handle_info(:check_store, socket) do
    Process.send_after(self(), :check_store, @ui_refresh, [])
    {:noreply, state_set(socket)}
  end

  def handle_event("view-entry", %{"value" => index_string}, socket) do
    {:noreply, assign(socket, entry: Catenary.string_to_index(index_string))}
  end

  def handle_event("connect", %{"value" => where}, socket) do
    {a, l, e} = index = Catenary.string_to_index(where)

    %Baobab.Entry{payload: payload} = Baobab.log_entry(a, e, log_id: l)

    {:ok, map, ""} = CBOR.decode(payload)
    {:ok, pid} = Baby.connect(map["host"], map["port"])

    {:noreply,
     assign(socket, connections: [{pid, Map.put(map, :id, index)} | socket.assigns.connections])}
  end

  def handle_event("nav", %{"value" => move}, socket) do
    {a, l, e} = socket.assigns.entry

    {na, nl, ne} =
      case move do
        "prev-entry" ->
          {a, l, e - 1}

        "next-entry" ->
          {a, l, e + 1}

        "next-author" ->
          next_author({a, l, e}, socket)

        "prev-author" ->
          prev_author({a, l, e}, socket)

        _ ->
          {a, l, e}
      end

    max =
      socket.assigns.store
      |> Enum.reduce(1, fn
        {^na, ^nl, s}, _acc -> s
        _, acc -> acc
      end)

    next =
      cond do
        # Wrap around
        ne < 1 -> {na, nl, max}
        ne > max -> {na, nl, 1}
        true -> {na, nl, ne}
      end

    {:noreply, assign(socket, entry: next)}
  end

  def handle_event("sort", %{"value" => ordering}, socket) do
    [dir, by] = String.split(ordering, "-")

    {:noreply,
     state_set([dir: String.to_existing_atom(dir), by: String.to_existing_atom(by)], socket)}
  end

  defp state_set(socket), do: state_set(socket.assigns.sorter, socket)

  defp state_set(sorter, socket) do
    si = Baobab.stored_info()

    assign(socket,
      store: sorted_store(si, sorter),
      connections: check_connections(socket.assigns.connections, []),
      watering: watering(si),
      sorter: sorter
    )
  end

  defp check_connections([], acc), do: acc

  defp check_connections([{pid, map} | rest], acc) do
    case Process.alive?(pid) do
      true ->
        check_connections(rest, [{pid, map} | acc])

      false ->
        check_connections(rest, acc)
    end
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
    |> Enum.sort_by(fn m -> Map.get(m, "running") end, :desc)
    |> Enum.uniq_by(fn %{"host" => h, "port" => p} -> {h, p} end)
    |> Enum.take(4)
  end

  defp extract_recents([{a, l, e} | rest], now, acc) do
    try do
      %Baobab.Entry{payload: payload} = Baobab.log_entry(a, e, log_id: l)
      {:ok, map, ""} = CBOR.decode(payload)

      case map do
        %{"running" => ts} ->
          then = ts |> Timex.parse!("{ISO:Extended}")

          cond do
            Timex.diff(then, now, :hour) > -49 ->
              extract_recents(rest, now, [
                Map.merge(map, %{:id => {a, l, e}, "running" => then}) | acc
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
    |> Enum.sort_by(fn {a, _, _} -> a end, &Kernel.<=/2)
    |> Enum.sort_by(elem, comp)
  end

  defp next_author({author, log_id, seq}, socket) do
    possibles =
      socket.assigns.store |> Enum.filter(fn {_, l, _} -> log_id == l end) |> Enum.sort(:asc)

    case Enum.drop_while(possibles, fn {a, _, _} -> a <= author end) do
      [] -> List.first(possibles)
      [next | _] -> next
    end
    |> then(fn {a, l, _} -> {a, l, seq} end)

    # I recognise there is no relationship with the other seqnum
    # Exploration involves more kismet than determinism
  end

  defp prev_author({author, log_id, seq}, socket) do
    possibles =
      socket.assigns.store |> Enum.filter(fn {_, l, _} -> log_id == l end) |> Enum.sort(:desc)

    case Enum.drop_while(possibles, fn {a, _, _} -> a >= author end) do
      [] -> List.first(possibles)
      [next | _] -> next
    end
    |> then(fn {a, l, _} -> {a, l, seq} end)
  end
end
