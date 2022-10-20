defmodule CatenaryWeb.Live do
  use CatenaryWeb, :live_view
  alias Catenary.{Navigation, Oases}

  @ui_fast 1062
  @ui_slow 11131
  @indices [:tags, :references, :timelines, :aliases]

  def mount(_params, session, socket) do
    # Making sure these exist, but also faux docs
    {:asc, :desc, :author, :logid, :seq}
    Phoenix.PubSub.subscribe(Catenary.PubSub, "ui")

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
        %{"entry" => e} -> e
        _ -> {:profile, whoami}
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
         ui_speed: @ui_slow,
         view: view,
         extra_nav: :none,
         indexing: Enum.reduce(@indices, %{}, fn i, a -> Map.merge(a, %{i => :not_running}) end),
         entry: entry,
         tag: :all,
         connections: [],
         oases: [],
         clumps: clumps,
         clump_id: clump_id,
         identity: whoami,
         facet_id: facet_id
       },
       true
     )}
  end

  def render(%{view: :prefs} = assigns) do
    ~L"""
     <div class="max-h-screen w-100 grid grid-cols-3 gap-2 justify-center">
       <%= live_component(Catenary.Live.PrefsManager, id: :prefs, clumps: @clumps, clump_id: @clump_id, identity: @identity, identities: @identities, store: @store, facet_id: @facet_id) %>
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

  def render(%{view: :tags, tag: tag} = assigns) when is_binary(tag) and tag != "" do
    ~L"""
     <div class="max-h-screen w-100 grid grid-cols-3 gap-2 justify-center">
       <%= live_component(Catenary.Live.TagViewer, id: :tags, tag: @tag) %>
       <%= sidebar(assigns) %>
     </div>
    """
  end

  def render(%{view: :tags} = assigns) do
    ~L"""
     <div class="max-h-screen w-100 grid grid-cols-3 gap-2 justify-center">
       <%= live_component(Catenary.Live.TagExplorer, id: :tags, tag: @tag) %>
       <%= sidebar(assigns) %>
     </div>
    """
  end

  def render(%{view: :aliases} = assigns) do
    ~L"""
     <div class="max-h-screen w-100 grid grid-cols-3 gap-2 justify-center">
       <%= live_component(Catenary.Live.AliasExplorer, id: :aliases, alias: :all) %>
       <%= sidebar(assigns) %>
     </div>
    """
  end

  def render(%{view: :entries} = assigns) do
    ~L"""
    <div class="max-h-screen w-100 grid grid-cols-3 gap-2 justify-center">
      <%= live_component(Catenary.Live.EntryViewer, id: :entry, store: @store, entry: @entry, clump_id: @clump_id) %>
      <%= sidebar(assigns) %>
    </div>
    """
  end

  defp sidebar(assigns) do
    ~L"""
    <div>
      <%= live_component(Catenary.Live.Ident, id: :ident, identity: @identity, clump_id: @clump_id) %>
      <%= live_component(Catenary.Live.OasisBox, id: :recents, indexing: @indexing, connections: @connections, oases: @oases) %>
      <%= live_component(Catenary.Live.Navigation, id: :nav, entry: @entry, extra_nav: @extra_nav, identity: @identity, view: @view) %>
    </div>
    """
  end

  def handle_info(%{view: :prefs}, socket) do
    {:noreply, state_set(socket, %{view: :prefs})}
  end

  def handle_info(%{view: :aliases}, socket) do
    {:noreply, state_set(socket, %{view: :aliases})}
  end

  def handle_info(%{view: :dashboard}, socket) do
    {:noreply, push_redirect(socket, to: Routes.live_dashboard_path(socket, :home))}
  end

  def handle_info(%{entry: which}, socket) do
    {:noreply, state_set(socket, %{view: :entries, entry: which})}
  end

  def handle_info(%{tag: which}, socket) do
    {:noreply, state_set(socket, %{view: :tags, tag: which})}
  end

  def handle_info(:check_store, socket) do
    {:noreply, state_set(socket, %{}, true)}
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
       tag: :all,
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

  # I keep thinking I will write these with `phx-target` to the component
  # but then I realise I need the global state updates
  def handle_event("identity-change", %{"selection" => whom}, socket) do
    {:noreply, state_set(socket, %{identity: whom |> Baobab.b62identity()})}
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
        nil -> Baobab.create_identity(whom)
      end

    {:noreply, state_set(socket, %{identity: pk})}
  end

  def handle_event("new-id", _, socket), do: {:noreply, socket}

  def handle_event(<<"rename-id-", old::binary>>, %{"value" => tobe}, socket)
      when is_binary(tobe) and byte_size(tobe) > 0 do
    case Enum.find(socket.assigns.identities, fn {n, _} -> n == tobe end) do
      # We'll let this crash and not pay attention
      nil -> Baobab.rename_identity(old, tobe)
      # Refuse to rename over an extant name
      _ -> %{}
    end

    # We set this to make it obvious what happened
    # if anything
    {:noreply, state_set(socket, %{identity: tobe |> Baobab.b62identity()})}
  end

  def handle_event(<<"rename-id-", _::binary>>, _, socket), do: {:noreply, socket}

  def handle_event("tag-explorer", _, socket) do
    {:noreply, state_set(socket, %{view: :tags, tag: :all})}
  end

  def handle_event("toggle-posting", _, socket) do
    show_now =
      case socket.assigns.extra_nav do
        :posting -> :none
        _ -> :posting
      end

    {:noreply, state_set(socket, %{extra_nav: show_now})}
  end

  def handle_event("toggle-aliases", _, socket) do
    show_now =
      case socket.assigns.extra_nav do
        :aliases -> :none
        _ -> :aliases
      end

    {:noreply, state_set(socket, %{extra_nav: show_now})}
  end

  def handle_event("toggle-tags", _, socket) do
    show_now =
      case socket.assigns.extra_nav do
        :tags -> :none
        _ -> :tags
      end

    {:noreply, state_set(socket, %{extra_nav: show_now})}
  end

  def handle_event("view-entry", %{"value" => index_string}, socket) do
    {:noreply,
     state_set(socket, %{view: :entries, entry: Catenary.string_to_index(index_string)})}
  end

  def handle_event("view-tag", %{"value" => tag}, socket) do
    {:noreply, state_set(socket, %{view: :tags, tag: tag})}
  end

  def handle_event(
        "new-tag",
        %{"ref" => ref, "tag0" => tag0, "tag1" => tag1, "tag2" => tag2, "tag3" => tag3},
        socket
      ) do
    tags = Enum.reject([tag0, tag1, tag2, tag3], fn s -> s == "" end)
    references = Catenary.string_to_index(ref)

    %Baobab.Entry{author: a, log_id: l, seqnum: e} =
      %{
        "references" => [references],
        "tags" => tags,
        "published" => Timex.now() |> DateTime.to_string()
      }
      |> CBOR.encode()
      |> append_log_for_socket(749, socket)

    b62author = Baobab.b62identity(a)
    entry = {b62author, l, e}
    Catenary.Indices.index_tags([entry], socket.assigns.clump_id)
    Catenary.Indices.index_references([entry], socket.assigns.clump_id)
    {:noreply, state_set(socket, %{entry: entry})}
  end

  def handle_event(
        "new-alias",
        %{
          "alias" => ali,
          "ref" => ref,
          "whom" => whom
        },
        socket
      ) do
    %Baobab.Entry{author: a, log_id: l, seqnum: e} =
      %{
        "whom" => whom,
        "references" => [Catenary.string_to_index(ref)],
        "alias" => ali,
        "published" => Timex.now() |> DateTime.to_string()
      }
      |> CBOR.encode()
      |> append_log_for_socket(53, socket)

    b62author = Baobab.b62identity(a)
    entry = {b62author, l, e}
    Catenary.Indices.index_aliases(b62author, socket.assigns.clump_id)
    Catenary.Indices.index_references([entry], socket.assigns.clump_id)
    {:noreply, state_set(socket, %{entry: entry})}
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
    clump_id = socket.assigns.clump_id

    t =
      case title do
        "" ->
          try do
            %Baobab.Entry{payload: payload} =
              Baobab.log_entry(oa, oe, log_id: ol, clump_id: clump_id)

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
      |> append_log_for_socket(533, socket)

    entry = {Baobab.b62identity(a), l, e}
    Catenary.Indices.index_references([entry], socket.assigns.clump_id)

    {:noreply, state_set(socket, %{entry: entry})}
  end

  def handle_event("new-entry", %{"body" => body, "log_id" => "0"}, socket) do
    %Baobab.Entry{author: a, log_id: l, seqnum: e} = append_log_for_socket(body, 0, socket)
    entry = {Baobab.b62identity(a), l, e}
    {:noreply, state_set(socket, %{entry: entry})}
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
      |> append_log_for_socket(360_360, socket)

    entry = {Baobab.b62identity(a), l, e}
    Catenary.Indices.index_references([entry], socket.assigns.clump_id)

    {:noreply, state_set(socket, %{entry: entry})}
  end

  def handle_event("init-connect", _, socket) do
    clumps = Application.get_env(:catenary, :clumps)
    this_clump = Map.get(clumps, socket.assigns.clump_id)

    which = Keyword.get(this_clump, :fallback_node)

    case Baby.connect(Keyword.get(which, :host), Keyword.get(which, :port),
           identity: Catenary.id_for_key(socket.assigns.identity),
           clump_id: socket.assigns.clump_id
         ) do
      {:ok, pid} ->
        {:noreply, state_set(socket, %{connections: [{pid, %{}} | socket.assigns.connections]})}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("connect", %{"value" => where}, socket) do
    with {a, l, e} = index <- Catenary.string_to_index(where),
         %Baobab.Entry{payload: payload} <-
           Baobab.log_entry(a, e, log_id: l, clump_id: socket.assigns.clump_id),
         {:ok, map, ""} <- CBOR.decode(payload),
         {:ok, pid} =
           Baby.connect(map["host"], map["port"],
             identity: Catenary.id_for_key(socket.assigns.identity),
             clump_id: socket.assigns.clump_id
           ) do
      {:noreply,
       state_set(
         socket,
         %{
           connections: [{pid, Map.put(map, :id, index)} | socket.assigns.connections]
         }
       )}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("nav", %{"value" => motion}, socket) do
    assigns = socket.assigns

    {:noreply,
     state_set(socket, %{
       view: :entries,
       entry: Navigation.move_to(motion, assigns.entry, assigns.store, assigns.identity)
     })}
  end

  @prefs_keys Catenary.Preferences.keys()
  defp do_prefs([]), do: :ok

  defp do_prefs([{key, val} | rest]) when key in @prefs_keys do
    Catenary.Preferences.set(key, val)
    do_prefs(rest)
  end

  defp do_prefs([_ | rest]), do: do_prefs(rest)

  defp state_set(socket, from_caller, reup? \\ false) do
    full_socket = assign(socket, from_caller)
    do_prefs(from_caller |> Map.to_list())
    state = full_socket.assigns
    clump_id = state.clump_id
    sihash = Baobab.current_hash(:content, clump_id)

    {updated?, si} =
      case state.store_hash do
        ^sihash -> {false, state.store}
        _ -> {true, Baobab.stored_info(clump_id)}
      end

    ihash = Baobab.current_hash(:identity, clump_id)

    ids =
      case state.id_hash do
        ^ihash -> state.identities
        _ -> Baobab.identities()
      end

    indexing = check_indices(state, updated?, si)
    con = check_connections(state.connections, [])

    common = [
      identities: ids,
      id_hash: ihash,
      indexing: indexing,
      connections: con,
      store_hash: sihash
    ]

    {ui_speed, extra} =
      case updated? do
        true ->
          {@ui_fast,
           [
             store: si,
             oases: Oases.recents(si, clump_id, 4)
           ]}

        false ->
          speed =
            case con do
              [] -> @ui_slow
              _ -> @ui_fast
            end

          {speed, []}
      end

    if reup?, do: Process.send_after(self(), :check_store, ui_speed, [])

    assign(full_socket, common ++ extra)
  end

  defp check_indices(state, updated?, si) do
    Enum.reduce(@indices, %{}, fn w, a -> Map.merge(a, check_index(w, state, updated?, si)) end)
  end

  # We have to match on literals, so we macro this.
  # I expected something different
  for index <- @indices do
    defp check_index(unquote(index), %{indexing: %{unquote(index) => pid}} = state, updated?, si)
         when is_pid(pid) do
      case Process.alive?(pid) do
        true ->
          %{unquote(index) => pid}

        false ->
          idx = Map.merge(state.indexing, %{unquote(index) => :not_running})
          check_index(unquote(index), Map.merge(state, %{indexing: idx}), updated?, si)
      end
    end

    defp check_index(unquote(index), %{indexing: %{unquote(index) => :not_running}}, false, _si),
      do: %{unquote(index) => :not_running}
  end

  # FYI these Task.start items do not work as might be expected
  # We get the task pid, not the underlying task process pid
  # This might seem like the same thing, but it's not sometimes
  defp check_index(which, state, true, si) do
    {:ok, pid} =
      case which do
        :timelines ->
          Task.start(Catenary.Indices, :index_timelines, [si, state.clump_id])

        :aliases ->
          Task.start(Catenary.Indices, :index_aliases, [state.identity, state.clump_id])

        :tags ->
          Task.start(Catenary.Indices, :index_tags, [si, state.clump_id])

        :references ->
          Task.start(Catenary.Indices, :index_references, [si, state.clump_id])
      end

    %{which => pid}
  end

  defp check_connections([], acc), do: acc

  defp check_connections([{pid, _} = val | rest], acc) do
    case Process.alive?(pid) do
      true ->
        check_connections(rest, [val | acc])

      false ->
        check_connections(rest, acc)
    end
  end

  defp append_log_for_socket(contents, log_id, socket) do
    Baobab.append_log(contents, Catenary.id_for_key(socket.assigns.identity),
      log_id: QuaggaDef.facet_log(log_id, socket.assigns.facet_id),
      clump_id: socket.assigns.clump_id
    )
  end
end
