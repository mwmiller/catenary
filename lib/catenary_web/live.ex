defmodule CatenaryWeb.Live do
  use CatenaryWeb, :live_view

  @ui_fast 1062
  @ui_slow 57529

  def mount(_params, _session, socket) do
    # Making sure these exist, but also faux docs
    {:asc, :desc, :author, :logid, :seq}
    Phoenix.PubSub.subscribe(Catenary.PubSub, "ui")

    default_icons = :png

    entry =
      case connected?(socket) do
        true ->
          Process.send_after(self(), :check_store, @ui_fast, [])
          :random

        false ->
          :none
      end

    {:ok,
     state_set(
       assign(socket,
         store_hash: <<>>,
         store: [],
         ui_speed: @ui_slow,
         iconset: default_icons,
         extra_nav: :none,
         aliasing: false,
         indexing: false,
         entry: entry,
         connections: [],
         watering: [],
         identity: Application.get_env(:baby, :identity) |> Baobab.b62identity()
       )
     )}
  end

  def render(%{store: []} = assigns) do
    ~L"""
    <div>
      <h1>No data just yet</h1>
      <%= if @connections == []  do %>
        <button phx-click="init-connect">⇆ Sync with a well-known node ⇆</button>
      <% else %>
        ⥀ any minute now ⥀
      <% end %>
    </div>
    """
  end

  def render(assigns) do
    ~L"""
    <div class="h-screen w-100 border-1 grid grid-cols-3 gap-2 justify-center font-mono">
      <div class="col-span-2">
      <%= live_component(Catenary.Live.EntryViewer, id: :entry, store: @store, entry: @entry, iconset: @iconset) %>
    </div>
    <div>
      <%= live_component(Catenary.Live.Ident, id: :ident, identity: @identity, iconset: @iconset) %>
      <%= live_component(Catenary.Live.OasisBox, id: :recents, indexing: @indexing, aliasing: @aliasing, connections: @connections, watering: @watering, iconset: @iconset) %>
      <%= live_component(Catenary.Live.Navigation, id: :nav,
      entry: @entry, extra_nav: @extra_nav, identity: @identity, iconset: @iconset) %>
    </div>
    </div>
    """
  end

  def handle_info(%{icons: which}, socket) do
    {:noreply, assign(socket, iconset: which)}
  end

  def handle_info(%{identity: who}, socket) do
    whonow = Baobab.b62identity(who)
    # Sync is importantish here
    Catenary.Indices.index_aliases(whonow)
    {:noreply, assign(socket, identity: whonow)}
  end

  def handle_info(%{view: :dashboard}, socket) do
    {:noreply, push_redirect(socket, to: Routes.live_dashboard_path(socket, :home))}
  end

  def handle_info(%{entry: which}, socket) do
    {:noreply, assign(socket, entry: which)}
  end

  def handle_info(:check_store, socket) do
    {:noreply, state_set(socket)}
  end

  def handle_event("toggle-posting", _, socket) do
    show_now =
      case socket.assigns.extra_nav do
        :posting -> :none
        _ -> :posting
      end

    {:noreply, assign(socket, extra_nav: show_now)}
  end

  def handle_event("toggle-aliases", _, socket) do
    show_now =
      case socket.assigns.extra_nav do
        :aliases -> :none
        _ -> :aliases
      end

    {:noreply, assign(socket, extra_nav: show_now)}
  end

  def handle_event("view-entry", %{"value" => index_string}, socket) do
    {:noreply, assign(socket, entry: Catenary.string_to_index(index_string))}
  end

  def handle_event(
        "new-alias",
        %{
          "alias" => ali,
          "doref" => doref,
          "ref" => ref,
          "whom" => whom
        },
        socket
      ) do
    references =
      case doref == "include" do
        true -> [Catenary.string_to_index(ref)]
        false -> []
      end

    %Baobab.Entry{author: a, log_id: l, seqnum: e} =
      %{
        "whom" => whom,
        "references" => references,
        "alias" => ali,
        "published" => Timex.now() |> DateTime.to_string()
      }
      |> CBOR.encode()
      |> Baobab.append_log(Catenary.id_for_key(socket.assigns.identity), log_id: 53)

    {:noreply, state_set(assign(socket, entry: {Baobab.b62identity(a), l, e}))}
  end

  def handle_event(
        "new-entry",
        %{
          "body" => body,
          "log_id" => "533",
          "ref" => ref,
          "title" => title
        },
        socket
      ) do
    # Only single parent references, but maybe multiple children
    # We get a tuple here, we'll get an array back from CBOR
    {oa, ol, oe} = Catenary.string_to_index(ref)

    t =
      case title do
        "" ->
          try do
            %Baobab.Entry{payload: payload} = Baobab.log_entry(oa, oe, log_id: ol)
            {:ok, %{"title" => t}, ""} = CBOR.decode(payload)

            case t do
              <<"Re: ", _::binary>> -> t
              _ -> "Re: " <> t
            end
          rescue
            _ -> "Re: other post"
          end

        _ ->
          title
      end

    %Baobab.Entry{author: a, log_id: l, seqnum: e} =
      %{
        "body" => body,
        "references" => [[oa, ol, oe]],
        "title" => t,
        "published" => Timex.now() |> DateTime.to_string()
      }
      |> CBOR.encode()
      |> Baobab.append_log(Catenary.id_for_key(socket.assigns.identity), log_id: 533)

    {:noreply, assign(socket, entry: {Baobab.b62identity(a), l, e})}
  end

  def handle_event(
        "new-entry",
        %{"body" => body, "log_id" => "360360", "title" => title},
        socket
      ) do
    # There will be more things to handle in short order, so this looks verbose
    # but it's probably necessary
    %Baobab.Entry{author: a, log_id: l, seqnum: e} =
      %{"body" => body, "title" => title, "published" => Timex.now() |> DateTime.to_string()}
      |> CBOR.encode()
      |> Baobab.append_log(Catenary.id_for_key(socket.assigns.identity), log_id: 360_360)

    {:noreply, assign(socket, entry: {Baobab.b62identity(a), l, e})}
  end

  def handle_event("init-connect", _, socket) do
    # This fallback to the fallback is a bad idea long-term
    which =
      Application.get_env(:catenary, :fallback_node, host: "sally.nftease.online", port: 8483)

    {:ok, pid} = Baby.connect(Keyword.get(which, :host), Keyword.get(which, :port))
    {:noreply, state_set(assign(socket, connections: [{pid, %{}} | socket.assigns.connections]))}
  end

  def handle_event("connect", %{"value" => where}, socket) do
    {a, l, e} = index = Catenary.string_to_index(where)

    %Baobab.Entry{payload: payload} = Baobab.log_entry(a, e, log_id: l)

    {:ok, map, ""} = CBOR.decode(payload)
    {:ok, pid} = Baby.connect(map["host"], map["port"])

    {:noreply,
     state_set(
       assign(socket, connections: [{pid, Map.put(map, :id, index)} | socket.assigns.connections])
     )}
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

        "origin" ->
          self_random(socket.assigns)

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

  defp state_set(socket) do
    state = socket.assigns
    si = Baobab.stored_info()
    curr = si |> CBOR.encode() |> Blake2.hash2b()
    updated? = curr != state.store_hash

    dex = check_refindex(state.indexing, updated?, si)
    ali = check_aliases(state.aliasing, updated?, state.identity)
    con = check_connections(state.connections, [])

    common = [indexing: dex, connections: con, store_hash: curr, aliasing: ali]

    {ui_speed, extra} =
      case updated? do
        true ->
          {@ui_fast,
           [
             store: si,
             watering: watering(si)
           ]}

        false ->
          speed =
            case {dex, ali, con} do
              {false, false, []} -> @ui_slow
              _ -> @ui_fast
            end

          {speed, []}
      end

    Process.send_after(self(), :check_store, ui_speed, [])
    assign(socket, common ++ extra)
  end

  defp check_aliases(pid, _new, _data) when is_pid(pid) do
    case Process.alive?(pid) do
      true -> pid
      false -> false
    end
  end

  defp check_aliases(false, false, _data), do: false

  defp check_aliases(false, true, id) do
    {:ok, pid} = Task.start(Catenary.Indices, :index_aliases, [id])
    pid
  end

  # We can wait an extra cycle for another
  # reindexing if needed
  defp check_refindex(pid, _new, _si) when is_pid(pid) do
    case Process.alive?(pid) do
      true -> pid
      false -> false
    end
  end

  defp check_refindex(false, false, _si), do: false

  defp check_refindex(false, true, si) do
    {:ok, pid} = Task.start(Catenary.Indices, :index_references, [si])
    pid
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

  defp self_random(assigns) do
    whoami = Baobab.b62identity(assigns.identity)

    possibles =
      case assigns.store |> Enum.filter(fn {a, _, _} -> a == whoami end) do
        [] -> assigns.store
        ents -> ents
      end

    Enum.random(possibles)
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
