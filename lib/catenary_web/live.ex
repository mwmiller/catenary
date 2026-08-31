defmodule CatenaryWeb.Live do
  @moduledoc """
  Catenary's top-level Phoenix LiveView: mounting assigns, routing between views, and wiring the entry/navigation card components.
  """
  use CatenaryWeb, :live_view
  require Logger
  alias Catenary.{Display, LogWriter, Navigation, Preferences}

  def mount(params, session, socket) do
    # Making sure these exist, but also faux docs
    {:asc, :desc, :author, :logid, :seq}
    Phoenix.PubSub.subscribe(Catenary.PubSub, "ui")

    whoami = Preferences.get(:identity)
    clumps = Application.get_env(:catenary, :clumps)
    clump_id = Preferences.get(:clump_id)

    {view, entry} =
      case params["view"] do
        view_str when is_binary(view_str) and view_str != "" ->
          {String.to_existing_atom(view_str), :all}

        _ ->
          case session do
            %{"view" => v, "entry" => e} -> {v, e}
            _ -> {Preferences.get(:view), Preferences.get(:entry)}
          end
      end

    facet_id = Preferences.get(:facet_id)

    upsock =
      socket
      |> assign(:uploaded_files, [])
      |> allow_upload(:image, accept: ~w(.jpg .jpeg .png .gif), max_entries: 1)

    if connected?(socket) do
      {w, h} = Preferences.get(:winsize)
      push_event(upsock, "window-init", %{"width" => w, "height" => h})
    end

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
         extra_nav: :none,
         connect_open: false,
         manual: %{},
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

  defp three_column_layout(assigns) do
    ~H"""
    {explorebar(assigns)}
    <div class="max-h-screen w-full flex justify-center px-2 py-2 gap-3">
      {timeline_nav(assigns)}
      <div class="w-full max-w-4xl">
        {render_slot(@inner_block)}
      </div>
      {activitybar(assigns)}
    </div>
    """
  end

  def render(%{view: :prefs} = assigns) do
    ~H"""
    <.three_column_layout {assigns}>
      <.live_component
        module={Catenary.Live.PrefsManager}
        id={:prefs}
        clumps={@clumps}
        clump_id={@clump_id}
        identity={@identity}
        identities={@identities}
        store={@store}
        facet_id={@facet_id}
        aliases={@aliases}
      />
    </.three_column_layout>
    """
  end

  def render(%{view: :entries, entry: {:tag, tag}} = assigns) do
    assigns = assign(assigns, :tag, tag)

    ~H"""
    <.three_column_layout {assigns}>
      <.live_component module={Catenary.Live.TagViewer} id={:tags} entry={@tag} />
    </.three_column_layout>
    """
  end

  def render(%{view: :tags} = assigns) do
    ~H"""
    <.three_column_layout {assigns}>
      <.live_component module={Catenary.Live.TagExplorer} id={:tags} entry={@entry} />
    </.three_column_layout>
    """
  end

  def render(%{view: :images} = assigns) do
    ~H"""
    <.three_column_layout {assigns}>
      <.live_component
        module={Catenary.Live.ImageExplorer}
        id={:images}
        entry={:poster}
        aliases={@aliases}
      />
    </.three_column_layout>
    """
  end

  # shown_hash lets type-marking be reactive in the page
  # oases lets us know when thing might be moving
  def render(%{view: :unshown} = assigns) do
    ~H"""
    <.three_column_layout {assigns}>
      <.live_component
        module={Catenary.Live.UnshownExplorer}
        id={:unshown}
        which={@entry}
        clump_id={@clump_id}
        oases={@oases}
        shown_hash={@shown_hash}
      />
    </.three_column_layout>
    """
  end

  def render(%{view: :aliases} = assigns) do
    ~H"""
    <.three_column_layout {assigns}>
      <.live_component
        module={Catenary.Live.AliasExplorer}
        id={:aliases}
        alias={:all}
        aliases={@aliases}
      />
    </.three_column_layout>
    """
  end

  def render(%{view: :oases} = assigns) do
    ~H"""
    <.three_column_layout {assigns}>
      <.live_component
        module={Catenary.Live.OasisExplorer}
        id={:oases}
        oases={@oases}
        opened={@opened}
        aliases={@aliases}
        connect_open={@connect_open}
        manual={@manual}
        bootstrap={Catenary.bootstrap_node(@clump_id)}
      />
    </.three_column_layout>
    """
  end

  def render(%{view: :entries} = assigns) do
    ~H"""
    <.three_column_layout {assigns}>
      <.live_component
        module={Catenary.Live.EntryViewer}
        id={:entry}
        store={@store}
        identity={@identity}
        entry={@entry}
        clump_id={@clump_id}
        aliases={@aliases}
      />
    </.three_column_layout>
    """
  end

  defp explorebar(assigns) do
    ~H"""
    <div class="sticky top-0 z-10 bg-white dark:bg-slate-900 border-b border-slate-200 dark:border-slate-700">
      <div class="flex items-center justify-between min-w-0 px-2 py-1 gap-1">
        <!-- Left: clump + identity -->
        <div class="flex items-center gap-1 shrink-0 text-sm font-mono">
          <button
            phx-click="toview"
            value="prefs"
            class="hover:text-amber-700 dark:hover:text-amber-400 transition-colors"
          >
            {@clump_id}
          </button>
          <span class="text-slate-400 dark:text-slate-600 select-none">/</span>
          <button
            value="origin"
            phx-click="nav"
            title="Home"
            class="flex items-center gap-1 hover:text-amber-700 dark:hover:text-amber-400 transition-colors"
          >
            {Display.scaled_avatar(@identity, 2) |> Phoenix.HTML.raw()}
            <span class="truncate">{Display.linked_author(@identity, @aliases)}</span>
          </button>
        </div>

        <!-- Center: nav buttons -->
        <div class="flex items-center gap-0.5 overflow-x-auto flex-1 justify-center min-w-0 scrollbar-hide">
          <button
            class={[
              stack_color(@entry_back),
              "px-2 py-1 rounded hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors text-lg leading-none"
            ]}
            phx-click="nav-backward"
            title="Back"
          >⤶</button>
          <button
            value="tags"
            phx-click="toview"
            title="Tags"
            class="px-2 py-1 rounded hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors text-lg leading-none"
          >#</button>
          <button
            value="oases"
            phx-click="toview"
            title="Peers"
            class="px-2 py-1 rounded hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors text-lg leading-none"
          >⇆</button>
          <button
            value="unshown"
            phx-click="toview"
            title="Unshown"
            class="px-2 py-1 rounded hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors text-lg leading-none"
          >◎</button>
          <button
            value="aliases"
            phx-click="toview"
            title="Aliases"
            class="px-2 py-1 rounded hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors text-lg leading-none"
          >~</button>
          <button
            value="images"
            phx-click="toview"
            title="Images"
            class="px-2 py-1 rounded hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors text-lg leading-none"
          >▣</button>
          <button
            class={[
              stack_color(@entry_fore),
              "px-2 py-1 rounded hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors text-lg leading-none"
            ]}
            phx-click="nav-forward"
            title="Forward"
          >⤷</button>
        </div>

        <!-- Right: index status -->
        <div class="shrink-0">
          <.live_component module={Catenary.Live.IndexStatus} id={:indices} indexing={@indexing} />
        </div>
      </div>
    </div>
    """
  end

  def stack_color([]), do: "bg-slate-100 dark:bg-slate-800"
  def stack_color(_), do: "bg-slate-200 dark:bg-slate-700"

  defp activitybar(assigns) do
    ~H"""
    <div class="mt-5 min-h-[400px]">
      <.live_component
        module={Catenary.Live.Navigation}
        id={:nav}
        uploads={@uploads}
        entry={@entry}
        extra_nav={@extra_nav}
        identity={@identity}
        view={@view}
        aliases={@aliases}
        entry_fore={@entry_fore}
        entry_back={@entry_back}
        clump_id={@clump_id}
      />
    </div>
    """
  end

  defp timeline_nav(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-1 pt-4">
      <button value="prev-author" phx-click="nav" title="Prev author">↥</button>
      <button value="prev-entry" phx-click="nav" title="Prev entry">⇜</button>
      <button phx-click="toggle-none" title="None">⍟</button>
      <button value="next-entry" phx-click="nav" title="Next entry">⇝</button>
      <button value="next-author" phx-click="nav" title="Next author">↧</button>
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
    {:noreply, push_navigate(socket, to: ~p"/dashboard")}
  end

  def handle_info(%{view: view, entry: which}, socket) do
    {:noreply,
     state_set(
       socket,
       Navigation.move_to("specified", %{view: view, entry: which}, socket.assigns)
     )}
  end

  # Manual connect attempt timing: re-check every 2s, give up after 20s.
  @manual_check_interval 2_000
  @manual_connect_timeout 20_000

  # Each manual peer is tracked independently in the `:manual` map, keyed by
  # {host, port}. Each attempt is tagged with a generation number so that
  # messages from a cancelled earlier attempt (already in the mailbox when
  # timers were cancelled) cannot corrupt the state of the current one.
  def handle_info({:manual_connect_check, target, attempt}, socket) do
    case current_manual_entry(socket, target, attempt) do
      %{state: :connecting} = entry ->
        {:noreply, manual_connect_progress(target, entry, socket)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:manual_connect_timeout, target, attempt}, socket) do
    case current_manual_entry(socket, target, attempt) do
      %{state: :connecting} = entry ->
        {:noreply, put_manual_entry(socket, target, %{entry | state: :failed})}

      _ ->
        {:noreply, socket}
    end
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

  def handle_event("reindex", _, socket) do
    Catenary.Indices.force_rebuild()
    {:noreply, socket}
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

  def handle_event("drop-id", %{"name" => whom}, socket) do
    Baobab.Identity.drop(whom)

    {:noreply, state_set(socket, %{identities: Baobab.Identity.list()})}
  end

  def handle_event("drop-id", _, socket), do: {:noreply, socket}

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
        ^tog -> :none
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

  def handle_event("set-connect-mode", %{"value" => mode}, socket) do
    connect_open = mode == "manual"
    {:noreply, assign(socket, connect_open: connect_open)}
  end

  def handle_event("connect-manual", %{"host" => host, "port" => port}, socket) do
    case parse_peer(host, port) do
      {:ok, host, port} ->
        Logger.debug(["Manual connection opening to ", host, ":", to_string(port), "..."])
        connector_wrap(host, port, socket)
        start_manual_connect(socket, host, port)

      :error ->
        Logger.warning(["Ignoring malformed manual connection target: ", host, ":", port])
        {:noreply, state_set(socket, %{})}
    end
  end

  def handle_event("connect-manual", _, socket), do: {:noreply, socket}

  def handle_event("nav", %{"value" => motion}, socket) do
    {:noreply, state_set(socket, Navigation.move_to(motion, :current, socket.assigns))}
  end

  # Menu selections from the native (Tauri) menu bar.
  def handle_event("menu", %{"view" => "dashboard"}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/dashboard")}
  end

  def handle_event("menu", %{"view" => view, "entry" => entry}, socket) do
    {:noreply,
     state_set(
       socket,
       Navigation.move_to(
         "specified",
         %{view: String.to_existing_atom(view), entry: menu_entry(entry)},
         socket.assigns
       )
     )}
  end

  def handle_event("menu", _, socket), do: {:noreply, socket}

  # The native window reports its size back so we can remember it.
  def handle_event("window-resize", %{"width" => width, "height" => height}, socket) do
    with {w, ""} <- Integer.parse(width),
         {h, ""} <- Integer.parse(height),
         true <- w > 0 and h > 0 do
      Preferences.set(:winsize, {w, h})
    end

    {:noreply, socket}
  end

  def handle_event("window-resize", _, socket), do: {:noreply, socket}

  defp menu_entry("none"), do: :none
  defp menu_entry("all"), do: :all
  defp menu_entry(entry) when is_binary(entry), do: String.to_existing_atom(entry)

  @prefs_keys Preferences.keys()
  defp do_prefs([]), do: :ok

  defp do_prefs([{key, val} | rest]) when key in @prefs_keys do
    Preferences.set(key, val)
    do_prefs(rest)
  end

  defp do_prefs([_ | rest]), do: do_prefs(rest)

  defp state_set(socket, from_caller) when is_map(from_caller) do
    full_socket = assign(socket, from_caller)
    do_prefs(from_caller |> Map.to_list())
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

  defp state_set(socket, _from_caller), do: socket

  defp connector_wrap(host, port, socket) do
    Baby.connect(host, port,
      identity: Catenary.id_for_key(socket.assigns.identity),
      clump_id: socket.assigns.clump_id
    )
  end

  # Manual peer targets with separate host and port entry fields. The host is
  # passed through as entered (bare IPv6 addresses need no unwrapping).
  defp parse_peer(host, port) when is_binary(host) and is_binary(port) do
    host = String.trim(host)

    with true <- byte_size(host) > 0,
         {port, ""} <- Integer.parse(String.trim(port)),
         true <- port > 0 and port <= 65_535 do
      {:ok, host, port}
    else
      _ -> :error
    end
  end

  defp parse_peer(_, _), do: :error

  # Manual connect attempt lifecycle: :connecting -> :connected | :failed.
  # The connection is re-checked periodically and declared failed after the
  # timeout, since Baby.connect gives no synchronous failure signal.

  defp start_manual_connect(socket, host, port) do
    target = {host, port}
    cancel_manual_timers(socket, target)
    prior = socket.assigns[:manual][target]
    attempt = ((prior && prior.attempt) || 0) + 1

    check =
      Process.send_after(self(), {:manual_connect_check, target, attempt}, @manual_check_interval)

    timeout =
      Process.send_after(
        self(),
        {:manual_connect_timeout, target, attempt},
        @manual_connect_timeout
      )

    entry = %{state: :connecting, attempt: attempt, check_timer: check, timeout_timer: timeout}
    {:noreply, put_manual_entry(socket, target, entry)}
  end

  # Retry every @manual_check_interval until the connection shows up or the
  # timeout fires; each reschedule keeps the current attempt number.
  defp manual_connect_progress(target, entry, socket) do
    {host, port} = target

    if manual_connected?(host, port) do
      Process.cancel_timer(entry.timeout_timer)
      put_manual_entry(socket, target, %{entry | state: :connected})
    else
      check =
        Process.send_after(
          self(),
          {:manual_connect_check, target, entry.attempt},
          @manual_check_interval
        )

      put_manual_entry(socket, target, %{entry | check_timer: check})
    end
  end

  # The live entry for a target, but only if it is the generation we expect.
  defp current_manual_entry(socket, target, attempt) do
    case socket.assigns[:manual][target] do
      %{attempt: ^attempt} = entry -> entry
      _ -> nil
    end
  end

  defp put_manual_entry(socket, target, entry) do
    state_set(socket, %{manual: Map.put(socket.assigns[:manual] || %{}, target, entry)})
  end

  # Stop the timers of any previous attempt for this target only; attempts
  # against other targets continue undisturbed.
  defp cancel_manual_timers(socket, target) do
    case socket.assigns[:manual][target] do
      nil ->
        :ok

      entry ->
        if t = entry.check_timer, do: Process.cancel_timer(t)
        if t = entry.timeout_timer, do: Process.cancel_timer(t)
    end
  end

  # Whether the manually entered peer already has an active connection, so the
  # UI can mirror the explorer's connected/attempting-sync indicators. Both
  # address families are tried, since either may be in use.
  defp manual_connected?(host, port) when is_binary(host) and is_integer(port) do
    charlist = String.to_charlist(host)
    active = Baby.Connection.Registry.active()

    Enum.any?([:inet, :inet6], fn family ->
      case :inet.getaddr(charlist, family) do
        {:ok, addr} -> {addr, port} in active
        _ -> false
      end
    end)
  end

  defp manual_connected?(_, _), do: false
end
