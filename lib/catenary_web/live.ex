defmodule CatenaryWeb.Live do
  use CatenaryWeb, :live_view
  require Logger
  alias Catenary.{Display, Navigation, LogWriter, Preferences}

  def mount(_params, session, socket) do
    # Making sure these exist, but also faux docs
    {:asc, :desc, :author, :logid, :seq}
    Phoenix.PubSub.subscribe(Catenary.PubSub, "ui")

    whoami = Preferences.get(:identity)
    clumps = Application.get_env(:catenary, :clumps)
    clump_id = Preferences.get(:clump_id)

    {view, entry} =
      case session do
        %{"view" => v, "entry" => e} -> {v, e}
        _ -> {Preferences.get(:view), Preferences.get(:entry)}
      end

    facet_id = Preferences.get(:facet_id)

    # Enable context menu in webview
    # Its nice enough I guess, but mostly here as a reminder
    # that I want to figure out how to enable my unicode keyboard
    # and other conveniences.
    :wx.set_env(Desktop.Env.wx_env())

    CatenaryWindow
    |> Desktop.Window.webview()
    |> :wxWebView.enableContextMenu()

    # At present this only happens in the profile page
    # It might be better to have this and the associate logic there
    # But my previous factorings have evertyhign here, so this one is too for now

    upsock =
      socket
      |> assign(:uploaded_files, [])
      |> allow_upload(:image, accept: ~w(.jpg .jpeg .png .gif), max_entries: 1)

    if Preferences.get(:autosync) and connected?(socket), do: Process.send(self(), :sync, [])

    {:ok,
     state_set(
       upsock,
       %{
         store_hash: Baobab.Persistence.content_hash(clump_id),
         store: Baobab.stored_info(clump_id),
         identities: Baobab.Identity.list(),
         shown_hash: Preferences.shown_hash(),
         aliases: Catenary.alias_state(),
         profile_items: Catenary.profile_items_state(),
         view: view,
         extra_nav: :stack,
         indexing: Catenary.Indices.status(),
         entry: entry,
         entry_fore: [],
         entry_back: [],
         oases: {:reload, []},
         me: self(),
         opened: 0,
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

  def render(%{view: :entries, entry: {:tag, tag}} = assigns) do
    ~L"""
     <%= explorebar(assigns) %>
     <div class="max-h-screen w-100 grid grid-cols-3 gap-2 justify-center">
       <%= live_component(Catenary.Live.TagViewer, id: :tags, entry: tag ) %>
       <%= activitybar(assigns) %>
     </div>
    """
  end

  def render(%{view: :tags} = assigns) do
    ~L"""
     <%= explorebar(assigns) %>
     <div class="max-h-screen w-100 grid grid-cols-3 gap-2 justify-center">
       <%= live_component(Catenary.Live.TagExplorer, id: :tags, entry: @entry) %>
       <%= activitybar(assigns) %>
     </div>
    """
  end

  def render(%{view: :images} = assigns) do
    ~L"""
     <%= explorebar(assigns) %>
     <div class="max-h-screen w-100 grid grid-cols-3 gap-2 justify-center">
       <%= live_component(Catenary.Live.ImageExplorer, id: :images, entry: :poster, aliases: @aliases) %>
       <%= activitybar(assigns) %>
     </div>
    """
  end

  # shown_hash lets type-marking be reactive in the page
  # oases lets us know when thing might be moving
  def render(%{view: :unshown} = assigns) do
    ~L"""
     <%= explorebar(assigns) %>
     <div class="max-h-screen w-100 grid grid-cols-3 gap-2 justify-center">
       <%= live_component(Catenary.Live.UnshownExplorer, id: :unshown, which: @entry, clump_id: @clump_id, oases: @oases, shown_hash: @shown_hash) %>
       <%= activitybar(assigns) %>
     </div>
    """
  end

  def render(%{view: :aliases} = assigns) do
    ~L"""
       <%= explorebar(assigns) %>
     <div class="max-h-screen w-100 grid grid-cols-3 gap-2 justify-center">
       <%= live_component(Catenary.Live.AliasExplorer, id: :aliases, alias: :all, aliases: @aliases) %>
       <%= activitybar(assigns) %>
     </div>
    """
  end

  def render(%{view: :entries} = assigns) do
    ~L"""
       <%= explorebar(assigns) %>
    <div class="max-h-screen w-100 grid grid-cols-3 gap-2 justify-center">
      <%= live_component(Catenary.Live.EntryViewer, id: :entry, store: @store, identity: @identity, entry: @entry, clump_id: @clump_id, aliases: @aliases) %>
      <%= activitybar(assigns) %>
    </div>
    """
  end

  defp explorebar(assigns) do
    ~L"""
        <div><button phx-click="toview" value="prefs"><%= @clump_id %></button> / <%= Display.linked_author(@identity, @aliases) %></div>
        <div class="w-max explore grid grid-cols-12">
        <button value="unshown" phx-click="toview">◎</button>
        <button value="tags" phx-click="toview">#</button>
        <button value="aliases" phx-click="toview">~</button>
        <button value="images" phx-click="toview">҂</button>
        </div>
    """
  end

  defp activitybar(assigns) do
    ~L"""
    <div>
      <%= live_component(Catenary.Live.IndexStatus, id: :indices, indexing: @indexing) %>
      <%= live_component(Catenary.Live.OasisBox, id: :recents, oases: @oases, opened: @opened, aliases: @aliases) %>
      <%= live_component(Catenary.Live.Navigation, id: :nav, uploads: @uploads, entry: @entry, extra_nav: @extra_nav, identity: @identity, view: @view, aliases: @aliases, entry_fore: @entry_fore, entry_back: @entry_back, clump_id: @clump_id) %>
    </div>
    """
  end

  def handle_info(<<"toggle-", _::binary>> = event, socket), do: handle_event(event, nil, socket)

  # This includes updating the index status, might as well do everything
  # until its proven slow
  def handle_info(:index_change, socket) do
    {:noreply, state_set(socket, %{})}
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

  def handle_info(:sync, socket) do
    case socket.assigns.oases do
      {_, []} ->
        {:noreply, socket}

      {:ok, possibles} ->
        %{id: id} = Enum.random(possibles)
        # About 17 minutes.  May become configurable.
        Process.send_after(self(), :sync, 1_020_979, [])
        handle_event("connect", %{"value" => Catenary.index_to_string(id)}, socket)
    end
  end

  def handle_event("profile-update", values, socket) do
    # A bit of munging
    vals =
      case Map.pop(values, "keep-avatar") do
        {"on", map} -> map
        {_, map} -> Map.put(map, "avatar", "")
      end
      |> Map.put("log_id", "360")

    handle_event("new-entry", vals, socket)
  end

  def handle_event("image-validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("image-save", _params, socket) do
    # It's limited to a single entry.. so I hope this matches
    [image_entry] =
      consume_uploaded_entries(socket, :image, fn %{path: path}, %{client_type: mime} = _entry ->
        %{
          "log_id" => QuaggaDef.base_log(mime) |> Integer.to_string(),
          "data" => File.read!(path)
        }
      end)

    handle_event("new-entry", image_entry, socket)
  end

  def handle_event("shown-set", %{"value" => entries_string}, socket) do
    Preferences.mark_entries(:shown, Catenary.string_to_index_list(entries_string))
    # Shown hash is updated on every state_set now
    {:noreply, state_set(socket, %{})}
  end

  def handle_event("toview", %{"value" => sview}, socket) do
    # This :all default might not make sense in the long-term
    # Its starting now. Under consideration 2023-09-03
    {:noreply, state_set(socket, %{view: String.to_existing_atom(sview), entry: :all})}
  end

  def handle_event("shown", %{"value" => mark}, socket) do
    case mark do
      "all" -> Preferences.mark_all_entries(:shown)
      "none" -> Preferences.mark_all_entries(:unshown)
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

  def handle_event("prefs-change", %{"_target" => [target]} = vals, socket) do
    # This idiom works for on change checkboxes.
    # Might want to extract.  Also, be careful on how "prefs-change" is used
    set_to =
      case vals do
        %{^target => "on"} -> true
        _ -> false
      end

    Preferences.set(String.to_existing_atom(target), set_to)
    {:noreply, socket}
  end

  def handle_event("clump-change", %{"clump_id" => clump_id}, socket) do
    # This is a heavy operation
    # It's essentially a whole new instance.
    # We need to drop a whole lot of state
    Catenary.Indices.reset()
    Catenary.State.reset()

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
  def handle_event("identity-change", %{"selection" => whom} = vals, socket) do
    case vals["drop"] do
      ^whom -> :noop
      other -> Baobab.Identity.drop(other)
    end

    {:noreply,
     state_set(socket, %{
       identity: whom |> Baobab.Identity.as_base62(),
       identities: Baobab.Identity.list()
     })}
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

    {:noreply, state_set(socket, %{identity: pk, identities: Baobab.Identity.list()})}
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
    {:noreply,
     state_set(socket, %{
       identity: tobe |> Baobab.Identity.as_base62(),
       identities: Baobab.Identity.list()
     })}
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

    connector_wrap(Keyword.get(which, :host), Keyword.get(which, :port), socket)
    {:noreply, state_set(socket, %{})}
  end

  def handle_event("connect", %{"value" => where}, socket) do
    with {a, l, e} <- Catenary.string_to_index(where),
         %Baobab.Entry{payload: payload} <-
           Baobab.log_entry(a, e, log_id: l, clump_id: socket.assigns.clump_id),
         {:ok, map, ""} <- CBOR.decode(payload) do
      Logger.debug(["Connection opening to ", map["name"], "..."])
      connector_wrap(map["host"], map["port"], socket)

      {:noreply, state_set(socket, %{})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("nav", %{"value" => motion}, socket) do
    {:noreply, state_set(socket, Navigation.move_to(motion, :current, socket.assigns))}
  end

  @prefs_keys Preferences.keys()
  defp do_prefs([]), do: :ok

  defp do_prefs([{key, val} | rest]) when key in @prefs_keys do
    Preferences.set(key, val)
    do_prefs(rest)
  end

  defp do_prefs([_ | rest]), do: do_prefs(rest)

  defp state_set(socket, from_caller) do
    full_socket = assign(socket, from_caller)
    # We get winsize too often, but
    #  - cannot find an exvent for change
    #  - preferences get auto-updated here
    do_prefs(Map.merge(from_caller, %{winsize: get_winsize()}) |> Map.to_list())
    state = full_socket.assigns
    clump_id = state.clump_id
    shash = Baobab.Persistence.content_hash(clump_id)

    # The index update here is excessive.
    si =
      case state.store_hash do
        ^shash ->
          state.store

        _ ->
          Catenary.Indices.update()
          Baobab.stored_info(clump_id)
      end

    assign(full_socket,
      aliases: Catenary.alias_state(),
      profile_items: Catenary.profile_items_state(),
      indexing: Catenary.Indices.status(),
      shown_hash: Preferences.shown_hash(),
      store_hash: shash,
      store: si,
      oases: Catenary.oasis_state(),
      # This is a place holder for interesting stats later
      # It is needed to make onboarding less confusing for now
      opened: Baby.Connection.Registry.active() |> Enum.count()
    )
  end

  defp connector_wrap(host, port, socket) do
    Baby.connect(host, port,
      identity: Catenary.id_for_key(socket.assigns.identity),
      clump_id: socket.assigns.clump_id
    )
  end

  defp get_winsize() do
    :wx.set_env(Desktop.Env.wx_env())
    Desktop.Window.webview(CatenaryWindow) |> :wxWindow.getSize()
  end
end
