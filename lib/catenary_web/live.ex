defmodule CatenaryWeb.Live do
  use CatenaryWeb, :live_view
  alias Catenary.{Navigation, Oases, LogWriter}

  @indices [:tags, :references, :timelines, :aliases, :graph, :reactions]

  def mount(_params, session, socket) do
    # Making sure these exist, but also faux docs
    {:asc, :desc, :author, :logid, :seq}
    Phoenix.PubSub.subscribe(Catenary.PubSub, "ui")
    Phoenix.PubSub.subscribe(Catenary.PubSub, "background")

    whoami = Catenary.Preferences.get(:identity)
    clumps = Application.get_env(:catenary, :clumps)
    clump_id = Catenary.Preferences.get(:clump_id)

    view =
      case session do
        %{"view" => v} -> v
        _ -> Catenary.Preferences.get(:view)
      end

    entry =
      case session do
        %{"entry" => e} ->
          e

        _ ->
          Catenary.Preferences.get(:entry)
      end

    facet_id = Catenary.Preferences.get(:facet_id)

    # Enable context menu in webview
    # Its nice enough I guess, but mostly here as a reminder
    # that I want to figure out how to enable my unicode keyboard
    # and other conveniences.
    :wx.set_env(Desktop.Env.wx_env())

    CatenaryWindow
    |> Desktop.Window.webview()
    |> :wxWebView.enableContextMenu()

    {:ok,
     state_set(
       socket,
       %{
         store_hash: <<>>,
         store: [],
         id_hash: <<>>,
         identities: [],
         aliases: {:out_of_date, %{}},
         view: view,
         extra_nav: :stack,
         indexing: Enum.reduce(@indices, %{}, fn i, a -> Map.merge(a, %{i => :not_running}) end),
         entry: entry,
         entry_fore: [],
         entry_back: [],
         connections: [],
         oases: [],
         clumps: clumps,
         clump_id: clump_id,
         identity: whoami,
         facet_id: facet_id
       }
     )}
  end

  def render(%{view: :prefs} = assigns) do
    ~L"""
     <div class="max-h-screen w-100 grid grid-cols-3 gap-2 justify-center">
       <%= live_component(Catenary.Live.PrefsManager, id: :prefs, clumps: @clumps, clump_id: @clump_id, identity: @identity, identities: @identities, store: @store, facet_id: @facet_id, aliases: @aliases) %>
     </div>
    """
  end

  def render(%{store: []} = assigns) do
    ~L"""
    <div>
      <h1>No data just yet</h1>
      <%= if @connections == [] do %>
        <button phx-click="init-connect">⇆ Get started on the <%= @clump_id %> network ⇆</button>
      <% else %>
        ⥀ any time now ⥀
      <% end %>
    </div>
    """
  end

  def render(%{view: :entries, entry: {:tag, tag}} = assigns) do
    ~L"""
     <div class="max-h-screen w-100 grid grid-cols-3 gap-2 justify-center">
       <%= live_component(Catenary.Live.TagViewer, id: :tags, entry: tag ) %>
       <%= sidebar(assigns) %>
     </div>
    """
  end

  def render(%{view: :tags} = assigns) do
    ~L"""
     <div class="max-h-screen w-100 grid grid-cols-3 gap-2 justify-center">
       <%= live_component(Catenary.Live.TagExplorer, id: :tags, entry: @entry) %>
       <%= sidebar(assigns) %>
     </div>
    """
  end

  def render(%{view: :unshown} = assigns) do
    ~L"""
     <div class="max-h-screen w-100 grid grid-cols-3 gap-2 justify-center">
       <%= live_component(Catenary.Live.UnshownExplorer, id: :unshown, which: @entry, clump_id: @clump_id, store_hash: @store_hash) %>
       <%= sidebar(assigns) %>
     </div>
    """
  end

  def render(%{view: :aliases} = assigns) do
    ~L"""
     <div class="max-h-screen w-100 grid grid-cols-3 gap-2 justify-center">
       <%= live_component(Catenary.Live.AliasExplorer, id: :aliases, alias: :all, aliases: @aliases) %>
       <%= sidebar(assigns) %>
     </div>
    """
  end

  def render(%{view: :entries} = assigns) do
    ~L"""
    <div class="max-h-screen w-100 grid grid-cols-3 gap-2 justify-center">
      <%= live_component(Catenary.Live.EntryViewer, id: :entry, store: @store, entry: @entry, clump_id: @clump_id, aliases: @aliases) %>
      <%= sidebar(assigns) %>
    </div>
    """
  end

  defp sidebar(assigns) do
    ~L"""
    <div>
      <%= live_component(Catenary.Live.Ident, id: :ident, identity: @identity, clump_id: @clump_id, aliases: @aliases) %>
      <%= live_component(Catenary.Live.IndexStatus, id: :indices, indexing: @indexing) %>
      <%= live_component(Catenary.Live.OasisBox, id: :recents, connections: @connections, oases: @oases, aliases: @aliases) %>
      <%= live_component(Catenary.Live.Navigation, id: :nav, entry: @entry, extra_nav: @extra_nav, identity: @identity, view: @view, aliases: @aliases, entry_fore: @entry_fore, entry_back: @entry_back, clump_id: @clump_id) %>
    </div>
    """
  end

  def handle_info(%{view: :dashboard}, socket) do
    {:noreply, push_redirect(socket, to: Routes.live_dashboard_path(socket, :home))}
  end

  def handle_info(%{view: view, entry: which}, socket) do
    {:noreply,
     state_set(
       socket,
       Navigation.move_to("specified", %{view: view, entry: which}, socket.assigns)
     )}
  end

  def handle_info({:refresh, :connection}, socket) do
    # Ongoing connection may have altered the store
    # Pray it does not alter it further.
    {:noreply, state_set(socket, %{})}
  end

  def handle_info({:completed, which}, %{assigns: assigns} = socket) do
    # This is non-atomically incorrect.  FIXME
    thehash = Baobab.Persistence.current_hash(:content, assigns.clump_id)

    update =
      case which do
        {:indexing, :aliases, _pid} ->
          %{
            aliases: Catenary.alias_state(),
            indexing: Map.merge(assigns.indexing, %{:aliases => thehash})
          }

        {:indexing, key, _pid} ->
          %{indexing: Map.merge(assigns.indexing, %{key => thehash})}

        {:connection, ident} ->
          %{connections: Enum.reject(assigns.connections, fn {i, _map} -> i == ident end)}
      end

    {:noreply, state_set(socket, update)}
  end

  def handle_event("shown-set", %{"value" => entries_string}, socket) do
    Catenary.Preferences.mark_entries(:shown, Catenary.string_to_index_list(entries_string))
    {:noreply, state_set(socket, %{store_hash: ""})}
  end

  def handle_event("toview", %{"value" => sview}, socket) do
    # This :all default might not make sense in the long-term
    {:noreply, state_set(socket, %{view: String.to_existing_atom(sview), entry: :all})}
  end

  def handle_event("shown", %{"value" => mark}, socket) do
    case mark do
      "all" -> Catenary.Preferences.mark_all_entries(:shown)
      "none" -> Catenary.Preferences.mark_all_entries(:unshown)
      _ -> :ok
    end

    {:noreply, state_set(socket, %{})}
  end

  def handle_event("compact", %{"value" => "all"}, socket) do
    # All doesn't include any identities we control.
    # We are the source of truth for these logs.
    our_pks = socket.assigns.identities |> Enum.map(fn {_n, k} -> k end)

    socket.assigns.store
    |> Enum.reject(fn {a, _, _} -> a in our_pks end)
    |> Enum.each(fn {a, l, _} ->
      Baobab.compact(a, log_id: l, clump_id: socket.assigns.clump_id)
    end)

    {:noreply, state_set(socket, %{})}
  end

  def handle_event("clump-change", %{"clump_id" => clump_id}, socket) do
    # This is a heavy operation
    # It's essentially a whole new instance.
    # We need to drop a whole lot of state
    Catenary.Indices.clear_all()

    {:noreply,
     state_set(socket, %{
       clump_id: clump_id,
       view: :entries,
       entry: {:profile, socket.assigns.identity}
     })}
  end

  def handle_event("facet-change", %{"value" => facet_id}, socket) do
    # Lots of ways to end up at `0`
    fid =
      case Integer.parse(facet_id) do
        {n, _} ->
          cond do
            n < 0 -> 0
            n > 255 -> 0
            true -> n
          end

        _ ->
          0
      end

    {:noreply, state_set(socket, %{facet_id: fid})}
  end

  # There should always be a selection.  Make sure it's not being dropped
  def handle_event("identity-change", %{"selection" => whom, "drop" => whom}, socket) do
    {:noreply, state_set(socket, %{identity: whom |> Baobab.Identity.as_base62()})}
  end

  def handle_event("identity-change", %{"selection" => whom, "drop" => doom}, socket) do
    :ok = Baobab.Identity.drop(doom)
    {:noreply, state_set(socket, %{identity: whom |> Baobab.Identity.as_base62()})}
  end

  def handle_event("identity-change", %{"selection" => whom}, socket) do
    {:noreply, state_set(socket, %{identity: whom |> Baobab.Identity.as_base62()})}
  end

  # A lot of overhead for a no-op.  Discover how to do this properly
  def handle_event("identity-change", _, socket), do: {:noreply, socket}

  # Empty is technically legal and works.  Just bad UX
  def handle_event("new-id", %{"value" => whom}, socket)
      when is_binary(whom) and byte_size(whom) > 0 do
    # We auto-switch to new identity.  Switching is cheap.
    # If they give the same name, just switch to it, don't overwrite
    # Let's make deletion explicit!
    pk =
      case Enum.find(socket.assigns.identities, fn {n, _} -> n == whom end) do
        {^whom, key} -> key
        nil -> Baobab.Identity.create(whom)
      end

    {:noreply, state_set(socket, %{identity: pk})}
  end

  def handle_event("new-id", _, socket), do: {:noreply, socket}

  def handle_event(<<"rename-id-", old::binary>>, %{"value" => tobe}, socket)
      when is_binary(tobe) and byte_size(tobe) > 0 do
    case Enum.find(socket.assigns.identities, fn {n, _} -> n == tobe end) do
      # We'll let this crash and not pay attention
      nil -> Baobab.Identity.rename(old, tobe)
      # Refuse to rename over an extant name
      _ -> %{}
    end

    # We set this to make it obvious what happened
    # if anything
    {:noreply, state_set(socket, %{identity: tobe |> Baobab.Identity.as_base62()})}
  end

  def handle_event(<<"rename-id-", _::binary>>, _, socket), do: {:noreply, socket}

  def handle_event("tag-explorer", _, socket) do
    {:noreply, state_set(socket, %{view: :tags, entry: :all})}
  end

  def handle_event(<<"toggle-", which::binary>>, _, socket) do
    tog = String.to_atom(which)

    show_now =
      case socket.assigns.extra_nav do
        ^tog -> :stack
        _ -> tog
      end

    {:noreply, state_set(socket, %{extra_nav: show_now})}
  end

  def handle_event("view-entry", %{"value" => index_string}, socket) do
    {:noreply,
     state_set(
       socket,
       Navigation.move_to(
         "specified",
         %{view: :entries, entry: Catenary.string_to_index(index_string)},
         socket.assigns
       )
     )}
  end

  def handle_event("view-tag", %{"value" => tag}, socket) do
    {:noreply,
     state_set(
       socket,
       Navigation.move_to("specified", %{view: :entries, entry: {:tag, tag}}, socket.assigns)
     )}
  end

  def handle_event("nav-forward", _, socket) do
    {:noreply, state_set(socket, Navigation.move_to("forward", :current, socket.assigns))}
  end

  def handle_event("nav-backward", _, socket) do
    {:noreply, state_set(socket, Navigation.move_to("back", :current, socket.assigns))}
  end

  def handle_event("new-entry", values, socket) do
    {:noreply,
     state_set(
       socket,
       Navigation.move_to(
         "new",
         %{view: :entries, entry: LogWriter.new_entry(values, socket)},
         socket.assigns
       )
     )}
  end

  def handle_event("init-connect", _, socket) do
    clumps = Application.get_env(:catenary, :clumps)
    this_clump = Map.get(clumps, socket.assigns.clump_id)

    which = Keyword.get(this_clump, :fallback_node)

    ident = connector_wrap(Keyword.get(which, :host), Keyword.get(which, :port), socket)
    {:noreply, state_set(socket, %{connections: [{ident, %{}} | socket.assigns.connections]})}
  end

  def handle_event("connect", %{"value" => where}, socket) do
    with {a, l, e} = index <- Catenary.string_to_index(where),
         %Baobab.Entry{payload: payload} <-
           Baobab.log_entry(a, e, log_id: l, clump_id: socket.assigns.clump_id),
         {:ok, map, ""} <- CBOR.decode(payload) do
      ident = connector_wrap(map["host"], map["port"], socket)

      {:noreply,
       state_set(
         socket,
         %{
           connections: [{ident, Map.put(map, :id, index)} | socket.assigns.connections]
         }
       )}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("nav", %{"value" => motion}, socket) do
    {:noreply, state_set(socket, Navigation.move_to(motion, :current, socket.assigns))}
  end

  @prefs_keys Catenary.Preferences.keys()
  defp do_prefs([]), do: :ok

  defp do_prefs([{key, val} | rest]) when key in @prefs_keys do
    Catenary.Preferences.set(key, val)
    do_prefs(rest)
  end

  defp do_prefs([_ | rest]), do: do_prefs(rest)

  defp state_set(socket, from_caller) do
    full_socket = assign(socket, from_caller)
    do_prefs(from_caller |> Map.to_list())
    state = full_socket.assigns
    clump_id = state.clump_id
    shash = Baobab.Persistence.current_hash(:content, clump_id)

    si =
      case state.store_hash do
        ^shash -> state.store
        _ -> Baobab.stored_info(clump_id)
      end

    ihash = Baobab.Persistence.current_hash(:identity, clump_id)

    ids =
      case state.id_hash do
        ^ihash -> state.identities
        _ -> Baobab.Identity.list()
      end

    assign(full_socket,
      identities: ids,
      id_hash: ihash,
      indexing: check_indices(state, shash, si),
      store_hash: shash,
      store: si,
      oases: Oases.recents(si, clump_id, 4)
    )
  end

  defp check_indices(state, shash, si) do
    Enum.reduce(@indices, %{}, fn w, a -> Map.merge(a, check_index(w, state, shash, si)) end)
  end

  # We have to match on literals, so we macro this.
  # I expected something different
  for index <- @indices do
    defp check_index(unquote(index), %{indexing: %{unquote(index) => pid}} = state, shash, si)
         when is_pid(pid) do
      case Process.alive?(pid) do
        true ->
          %{unquote(index) => pid}

        false ->
          idx = Map.merge(state.indexing, %{unquote(index) => shash})
          check_index(unquote(index), Map.merge(state, %{indexing: idx}), shash, si)
      end
    end
  end

  defp check_index(which, state, shash, si) do
    new_state =
      case state.store_hash == shash do
        true ->
          shash

        false ->
          {:ok, pid} =
            case which do
              :timelines ->
                Task.start(Catenary.Indices, :index_timelines, [si, state.clump_id])

              :aliases ->
                Task.start(Catenary.Indices, :index_aliases, [state.identity, state.clump_id])

              :tags ->
                Task.start(Catenary.Indices, :index_tags, [si, state.clump_id])

              :reactions ->
                Task.start(Catenary.Indices, :index_reactions, [si, state.clump_id])

              :references ->
                Task.start(Catenary.Indices, :index_references, [si, state.clump_id])

              # This "index" is maintained in Baobab and is a heavy operation
              # it should perhaps be less often run
              :graph ->
                Task.start(Catenary.SocialGraph, :update_from_logs, [
                  state.identity,
                  state.clump_id
                ])
            end

          pid
      end

    %{which => new_state}
  end

  defp connector_wrap(host, port, socket) do
    # This should probably use `Process.spawn` with `:monitor`
    # Feel free to curse my name when that becomes true
    # We get the task pid, not the underlying task process pid
    # This might seem like the same thing, but it's not sometimes
    #
    done = fn ->
      Phoenix.PubSub.local_broadcast(
        Catenary.PubSub,
        "background",
        {:completed, {:connection, {host, port}}}
      )
    end

    refresh = fn ->
      Phoenix.PubSub.local_broadcast(
        Catenary.PubSub,
        "background",
        {:refresh, :connection}
      )
    end

    Task.start(fn ->
      with {:ok, pid} <-
             Baby.connect(host, port,
               identity: Catenary.id_for_key(socket.assigns.identity),
               clump_id: socket.assigns.clump_id
             ) do
        loop = fn p, i, f ->
          case Process.alive?(p) do
            true ->
              case rem(i, 7) do
                0 -> refresh.()
                _ -> :ok
              end

              Process.sleep(547)
              f.(p, i + 1, f)

            false ->
              done.()
          end
        end

        loop.(pid, 1, loop)
      else
        _ -> done.()
      end
    end)

    {host, port}
  end
end
