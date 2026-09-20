defmodule CatenaryWeb.Live do
  @moduledoc """
  Catenary's top-level Phoenix LiveView: mounting assigns, routing between views, and wiring the entry/navigation card components.
  """
  use CatenaryWeb, :live_view
  require Logger

  alias Catenary.{
    Games.Backgammon.Chain,
    Games.Backgammon.Game,
    Display,
    IndexWorker.Challenges,
    LogWriter,
    Navigation,
    Preferences
  }

  def mount(params, session, socket) do
    # Making sure these exist, but also faux docs
    {:asc, :desc, :author, :logid, :seq}
    Phoenix.PubSub.subscribe(Catenary.PubSub, "ui")

    whoami = Preferences.get(:identity)
    clumps = Application.get_env(:catenary, :clumps)
    clump_id = Preferences.get(:clump_id)

    {view, entry} =
      case params do
        %{"view" => view_str} when is_binary(view_str) and view_str != "" ->
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
          has_unshown: has_unshown_entries?(clump_id),
          has_identity_unshown_mentions: has_identity_unshown_mentions?(whoami),
          aliases: Catenary.alias_state(),
          profile_items: Catenary.profile_items_state(),
         view: view,
         extra_nav: :none,
         connect_mode: "announced",
         manual: %{},
         mdns_peers: [],
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
         facet_id: facet_id,
         accepted_logs: accepted_log_names(),
         index_version: 0
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
        index_version={@index_version}
        clumps={@clumps}
        clump_id={@clump_id}
        identity={@identity}
        identities={@identities}
        store={@store}
        facet_id={@facet_id}
        aliases={@aliases}
        accepted_logs={@accepted_logs}
        challenge_checked={
          Map.get(assigns, :challenge_checked, Preferences.accept_log_name?(:challenge))
        }
      />
    </.three_column_layout>
    """
  end

  def render(%{view: :entries, entry: {:tag, tag}} = assigns) do
    assigns = assign(assigns, :tag, tag)

    ~H"""
    <.three_column_layout {assigns}>
      <.live_component
        module={Catenary.Live.TagViewer}
        id={:tags}
        index_version={@index_version}
        entry={@tag}
      />
    </.three_column_layout>
    """
  end

  def render(%{view: :tags} = assigns) do
    ~H"""
    <.three_column_layout {assigns}>
      <.live_component
        module={Catenary.Live.TagExplorer}
        id={:tags}
        index_version={@index_version}
        entry={@entry}
      />
    </.three_column_layout>
    """
  end

  def render(%{view: :images} = assigns) do
    ~H"""
    <.three_column_layout {assigns}>
      <.live_component
        module={Catenary.Live.ImageExplorer}
        id={:images}
        index_version={@index_version}
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
        index_version={@index_version}
        entry={@entry}
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
        index_version={@index_version}
        entry={:all}
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
        index_version={@index_version}
        oases={@oases}
        opened={@opened}
        aliases={@aliases}
        connect_mode={@connect_mode}
        manual={@manual}
        mdns_peers={@mdns_peers}
        bootstrap={Catenary.bootstrap_node(@clump_id)}
      />
    </.three_column_layout>
    """
  end

  def render(%{view: :reactions} = assigns) do
    ~H"""
    <.three_column_layout {assigns}>
      <.live_component
        module={Catenary.Live.ReactionsExplorer}
        id={:reactions}
        index_version={@index_version}
        entry={:all}
        clump_id={@clump_id}
      />
    </.three_column_layout>
    """
  end

  def render(%{view: :challenges} = assigns) do
    ~H"""
    <.three_column_layout {assigns}>
      <.live_component
        module={Catenary.Live.ChallengesExplorer}
        id={:challenges}
        index_version={@index_version}
        entry={:all}
        identity={@identity}
        aliases={@aliases}
      />
    </.three_column_layout>
    """
  end

  def render(%{view: :game, entry: {:game, gid}} = assigns) do
    assigns = assign(assigns, game_id: gid)

    ~H"""
    <.three_column_layout {assigns}>
      <.live_component
        module={Catenary.Live.BackgammonView}
        id={:game}
        index_version={@index_version}
        game_id={@game_id}
        entry={@entry}
        identity={@identity}
        aliases={@aliases}
        clump_id={@clump_id}
        facet_id={@facet_id}
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
        index_version={@index_version}
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
            class={[
              if(@has_identity_unshown_mentions, do: "text-amber-600 dark:text-amber-400", else: ""),
              "flex items-center gap-1 hover:text-amber-700 dark:hover:text-amber-400 transition-colors"
            ]}
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
            disabled={@entry_back == []}
          >⤶</button>
          <button
            :if={Preferences.accept_log_name?(:challenge)}
            value="challenges"
            phx-click="toview"
            title="Challenges"
            class="px-2 py-1 rounded hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors text-lg leading-none"
          >⚄</button>
          <button
            :if={Preferences.accept_log_name?(:tag)}
            value="tags"
            phx-click="toview"
            title="Tags"
            class="px-2 py-1 rounded hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors text-lg leading-none"
          >#</button>
          <button
            :if={Preferences.accept_log_name?(:react)}
            value="reactions"
            phx-click="toview"
            title="Reactions"
            class="px-2 py-1 rounded hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors text-lg leading-none"
          >♥</button>
          <button
            value="unshown"
            phx-click="toview"
            title="Unshown"
            class={[
              if(@has_unshown, do: "text-amber-600 dark:text-amber-400", else: ""),
              "px-2 py-1 rounded hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors text-xl leading-none font-medium"
            ]}
          >◎</button>
          <button
            :if={
              Preferences.accept_log_name?(:gif) or Preferences.accept_log_name?(:png) or
                Preferences.accept_log_name?(:jpeg)
            }
            value="images"
            phx-click="toview"
            title="Images"
            class="px-2 py-1 rounded hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors text-lg leading-none"
          >▣</button>
          <button
            :if={Preferences.accept_log_name?(:alias)}
            value="aliases"
            phx-click="toview"
            title="Aliases"
            class="px-2 py-1 rounded hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors text-lg leading-none"
          >~</button>
          <button
            :if={Preferences.accept_log_name?(:oasis)}
            value="oases"
            phx-click="toview"
            title="Peers"
            class="px-2 py-1 rounded hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors text-lg leading-none"
          >⇆</button>
          <button
            class={[
              stack_color(@entry_fore),
              "px-2 py-1 rounded hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors text-lg leading-none"
            ]}
            phx-click="nav-forward"
            title="Forward"
            disabled={@entry_fore == []}
          >⤷</button>
        </div>

        <!-- Right: index status -->
        <div class="shrink-0">
          <.live_component
            module={Catenary.Live.IndexStatus}
            id={:indices}
            index_version={@index_version}
            indexing={@indexing}
          />
        </div>
      </div>
    </div>
    """
  end

  def stack_color([]) do
    "disabled:opacity-40 disabled:cursor-default disabled:hover:bg-transparent"
  end

  def stack_color(_), do: ""

  defp has_unshown_entries?(clump_id) do
    shown = Catenary.Preferences.get(:shown) |> Map.get(clump_id, MapSet.new())
    Baobab.all_entries(clump_id) |> Enum.any?(fn entry -> not MapSet.member?(shown, entry) end)
  end

  defp has_identity_unshown_mentions?(identity) do
    case :ets.lookup(:mentions, {"", identity}) do
      [] ->
        false

      [{{"", ^identity}, items}] ->
        items |> Enum.any?(fn {_date, entry} -> not Preferences.shown?(entry) end)
    end
  end

  defp activitybar(assigns) do
    ~H"""
    <div class="mt-5 min-h-[400px]">
      <.live_component
        module={Catenary.Live.Navigation}
        id={:nav}
        index_version={@index_version}
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

  # Events forwarded from explorer LiveComponents
  def handle_info({module, event, payload}, socket)
      when is_atom(module) and is_binary(event) do
    handle_event(event, payload, socket)
  end

  # Index workers broadcast :index_change on the "ui" topic after every pass.
  # Bumping the monotonic version counter changes the parent's assigns, which
  # forces every LiveComponent in the current view to re-render and re-read
  # from the freshly-updated ETS tables (tags, reactions, mentions, etc.).
  #
  # Skip the expensive content_hash check: the index workers have already
  # processed the diff, so triggering another Indices.update() via the hash
  # gate would be redundant and creates a feedback loop during replication.
  def handle_info(:index_change, socket) do
    {:noreply,
     state_set(socket, %{index_version: socket.assigns.index_version + 1}, skip_hash: true)}
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

  # Manual connect attempt timing: give up after 20s if the connecting attempt
  # never establishes. Connection *events* (established or dropped) are pushed
  # in near-realtime by Catenary.ConnectionMonitor as :connections_changed.
  # A failed attempt is shown briefly (@manual_failed_grace) before cleanup.
  @manual_connect_timeout 20_000
  @manual_failed_grace 5_000

  # The connection set changed (some peer connected or dropped). Refresh the
  # whole view and reconcile the manual-peer list against the live registry so
  # a connected peer is removed the moment its connection goes away, and a
  # connecting peer is promoted to connected as soon as it establishes.
  def handle_info(:connections_changed, socket) do
    {:noreply, state_set(socket, %{manual: reconcile_manual(socket)})}
  end

  # Each manual peer is tracked independently in the `:manual` map, keyed by
  # {host, port}. Each attempt is tagged with a generation number so that
  # messages from a cancelled earlier attempt (already in the mailbox when
  # timers were cancelled) cannot corrupt the state of the current one.
  def handle_info({:manual_connect_timeout, target, attempt}, socket) do
    case current_manual_entry(socket, target, attempt) do
      %{state: :connecting} = entry ->
        # Show the failure briefly so it is visible, then remove the entry.
        cleanup =
          Process.send_after(
            self(),
            {:manual_cleanup, target, attempt},
            @manual_failed_grace
          )

        {:noreply,
         put_manual_entry(
           socket,
           target,
           Map.merge(entry, %{state: :failed, cleanup_timer: cleanup})
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:manual_cleanup, target, attempt}, socket) do
    case current_manual_entry(socket, target, attempt) do
      %{state: :failed} ->
        {:noreply, remove_manual_entry(socket, target)}

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

  def handle_info({:mdns_peers, peers}, socket) do
    {:noreply, assign(socket, mdns_peers: peers)}
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
    case consume_uploaded_entries(socket, :image, fn %{path: path},
                                                     %{client_type: mime} = _entry ->
           %{
             "log_id" => QuaggaDef.base_log(mime) |> Integer.to_string(),
             "data" => File.read!(path)
           }
         end) do
      [image_entry] ->
        handle_event("new-entry", image_entry, %{
          socket
          | assigns: Map.put(socket.assigns, :extra_nav, :none)
        })

      [] ->
        {:noreply, socket}
    end
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

    # If we dropped the active identity, switch to another extant
    # one (creating a working default if none remain)
    new_identity =
      case Enum.filter(socket.assigns.identities, fn {n, _} -> n != whom end) do
        [{_n, key} | _] ->
          key

        [] ->
          Preferences.get(:identity)
      end

    Preferences.set(:identity, new_identity)

    {:noreply, state_set(socket, %{identity: new_identity, identities: Baobab.Identity.list()})}
  end

  def handle_event("drop-id", _, socket), do: {:noreply, socket}

  def handle_event("export-clumps", _params, socket) do
    content = Catenary.Config.export_config()
    {:noreply, push_event(socket, "export-save", %{content: content, filename: "clumps.toml"})}
  end

  def handle_event("export-identity", %{"name" => whom}, socket) do
    content =
      %{
        application: "catenary",
        identity: whom,
        key_encoding: "base62",
        key_type: "ed25519",
        public_key: Baobab.Identity.key(whom, :public) |> BaseX.Base62.encode(),
        secret_key: Baobab.Identity.key(whom, :secret) |> BaseX.Base62.encode()
      }
      |> Jason.encode!()

    {:noreply, push_event(socket, "export-save", %{content: content, filename: whom <> ".json"})}
  end

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
    tog = String.to_existing_atom(which)

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

  # Challenge log (777) actions from the Challenges area.

  # Family 0x1 (backgammon) uses a provably-fair scrypt chain; other families
  # are created without one (generated but not committed) for now.
  def handle_event("new-challenge", %{"family" => family} = params, socket) do
    publish_challenge(family, challenge_target(params), socket)
  end

  def handle_event("new-challenge", _, socket), do: {:noreply, socket}

  def handle_event("challenge-author", %{"value" => to}, socket) when is_binary(to) do
    publish_challenge(
      QuaggaDef.family_tag(:backgammon) |> Integer.to_string(),
      to,
      socket
    )
  end

  def handle_event("challenge-author", _, socket), do: {:noreply, socket}

  def handle_event(
        "accept-challenge",
        %{"value" => game_id, "family" => family} = accept_params,
        socket
      ) do
    with {tag, ""} <- Integer.parse(family),
         true <- tag >= 1 and tag <= 255,
         {:ok, gid} <- Base.decode16(game_id, case: :lower),
         challenger when is_binary(challenger) and challenger != "" <-
           Map.get(accept_params, "challenger") do
      {chain_commit, reveal} =
        if tag == QuaggaDef.family_tag(:backgammon) do
          chain = chain_seed(socket, gid, "accepter") |> Chain.generate()

          # Make the just-built chain available immediately: the game row is in
          # the table from the challenge, so my_reveals lands on it when the
          # accepter opens the game.
          Chain.cache_put(game_id, "accepter", chain)

          {
            chain |> Chain.commit() |> Base.encode16(case: :lower),
            chain |> List.last() |> Base.encode16(case: :lower)
          }
        end

      accept =
        %{
          "log_id" => "777",
          "type" => "accept",
          "game_id" => gid,
          "family" => tag,
          "player" => socket.assigns.identity,
          "role" => "accepter",
          "chain_spec" => Chain.spec(),
          "chain_commit" => chain_commit,
          "reveal" => reveal
        }

      LogWriter.new_entry(accept, socket)

      publish_play_entry(socket, gid, tag, challenger, chain_commit, reveal, accept_params)

      # Jump the challenges explorer to the Running tab so the just-accepted
      # game is visible (it leaves the Open list the moment the accepter is set).
      send_update(Catenary.Live.ChallengesExplorer, id: :challenges, tab: :running)

      # The explorer jumping to the Running tab with the live game row on it
      # is all the feedback an accept needs.
      {:noreply, state_set(socket, %{view: :challenges, entry: :all})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("withdraw-challenge", %{"value" => game_id}, socket) do
    case Base.decode16(game_id, case: :lower) do
      {:ok, gid} ->
        LogWriter.new_entry(
          %{"log_id" => "777", "type" => "withdraw", "game_id" => gid},
          socket
        )

        # The row leaving the Running list is all the feedback a withdraw
        # needs.
        {:noreply, state_set(socket, %{view: :challenges, entry: :all})}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("play-game", %{"value" => game_id}, socket) do
    if String.match?(game_id, ~r/^[0-9a-f]{64}$/) do
      # Skip state_set (which may trigger a heavy reindex) and jump straight
      # to the game view.  The game row is already in the :challenges ETS
      # table from the index worker, so BackgammonView can pick it up immediately.
      back = [
        %{
          view: socket.assigns.view,
          entry: socket.assigns.entry,
          entry_back: socket.assigns.entry_back,
          entry_fore: socket.assigns.entry_fore
        }
      ]

      {:noreply,
       assign(socket, %{
         view: :game,
         entry: {:game, game_id},
         entry_back: back ++ socket.assigns.entry_back,
         entry_fore: []
       })}
    else
      {:noreply, socket}
    end
  end

  def handle_event("publish-roll", %{"game_id" => game_id} = params, socket)
      when is_binary(game_id) do
    with {:ok, row} <- game_row(game_id),
         true <- row.mover == socket.assigns.identity,
         {:ok, remaining, r_cur, r_next} <- reveal_pair_for(row, socket),
         {:ok, gid} <- Base.decode16(game_id, case: :lower) do
      entry =
        Game.roll_entry(
          socket.assigns.identity,
          gid,
          get_in(row, [:opener, :rounds]) || 0,
          remaining,
          r_cur,
          r_next,
          note: Map.get(params, "note", "")
        )

      write_play_entry(socket, row, entry)
    end

    {:noreply, socket}
  end

  def handle_event("publish-roll", _, socket), do: {:noreply, socket}

  def handle_event("publish-turn", %{"game_id" => game_id} = params, socket)
      when is_binary(game_id) do
    with {:ok, row} <- game_row(game_id),
         true <- row.mover == socket.assigns.identity,
         {turn, ""} <- Integer.parse(Map.get(params, "turn", "")),
         roll when is_binary(roll) and roll != "" <- Map.get(params, "roll"),
         moves when is_binary(moves) <- Map.get(params, "moves", ""),
         {:ok, remaining, r_cur, r_next} <- reveal_pair_for(row, socket),
         {:ok, gid} <- Base.decode16(game_id, case: :lower) do
      entry =
        Game.turn_entry(
          socket.assigns.identity,
          gid,
          turn,
          roll,
          moves,
          r_cur,
          r_next,
          reveals: remaining,
          note: Map.get(params, "note", "")
        )

      write_play_entry(socket, row, entry)
    end

    {:noreply, socket}
  end

  def handle_event("publish-turn", _, socket), do: {:noreply, socket}

  def handle_event("publish-resign", %{"game_id" => game_id} = params, socket)
      when is_binary(game_id) do
    with {:ok, row} <- game_row(game_id),
         true <- row.mover == socket.assigns.identity,
         {turn, ""} <- Integer.parse(Map.get(params, "turn", "")),
         {:ok, gid} <- Base.decode16(game_id, case: :lower) do
      entry =
        Game.resign_entry(
          socket.assigns.identity,
          gid,
          turn,
          note: Map.get(params, "note", "")
        )

      write_play_entry(socket, row, entry)
    end

    {:noreply, socket}
  end

  def handle_event("publish-resign", _, socket), do: {:noreply, socket}

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

  def handle_event("accept-change", values, socket) do
    all_log_names =
      QuaggaDef.log_defs() |> Enum.map(fn {_k, v} -> v.name end)

    checked =
      all_log_names
      |> Enum.filter(fn name -> Map.has_key?(values, "log_name-#{name}") end)
      |> MapSet.new()

    challenge_checked = MapSet.member?(checked, :challenge)

    {:noreply,
     socket
     |> assign(accepted_logs: checked)
     |> assign(challenge_checked: challenge_checked)}
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

  def handle_event("set-connect-mode", %{"value" => mode}, socket)
      when mode in ["announced", "peers", "manual", "mdns"] do
    socket = assign(socket, connect_mode: mode)

    socket =
      if mode in ["peers", "mdns"] and socket.assigns.mdns_peers == [] do
        trigger_mdns_browse(socket)
      else
        socket
      end

    {:noreply, socket}
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

  def handle_event("browse-mdns", _params, socket) do
    socket = trigger_mdns_browse(socket)
    {:noreply, socket}
  end

  def handle_event("connect-mdns", %{"ip" => ip_str, "port" => port_str}, socket) do
    with {:ok, ip} <- :inet.parse_address(String.to_charlist(ip_str)),
         {port, ""} <- Integer.parse(port_str) do
      host = :inet.ntoa(ip) |> to_string()
      connector_wrap(host, port, socket)
      start_manual_connect(socket, host, port)
    else
      _ -> {:noreply, socket}
    end
  end

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

  def handle_event("menu", %{"value" => motion}, socket) do
    {:noreply, state_set(socket, Navigation.move_to(motion, :current, socket.assigns))}
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

  defp game_row(game_id) do
    case Challenges.game(game_id) do
      nil -> :error
      row -> {:ok, row}
    end
  end

  # The mover-author's own next two reveals, straight from their cached chain
  # and the fold's live remaining count. Mirrors BackgammonView.my_reveals so the
  # roll the play UI showed is exactly what lands on the log.
  defp reveal_pair_for(row, socket) do
    identity = socket.assigns.identity
    role = game_role(row, identity)

    with role when is_binary(role) <- role,
         remaining when is_integer(remaining) and remaining >= 2 <-
           Map.get(row, :remaining, %{})
           |> Map.get(identity, Chain.spec()["length"]),
         chain when is_list(chain) <- chain_for(row, role, socket),
         {r_cur, r_next} <- Chain.reveal_pair(chain, remaining) do
      {:ok, remaining, r_cur, r_next}
    else
      _ -> :error
    end
  end

  defp game_role(row, identity) do
    cond do
      identity == row.challenger -> "challenger"
      identity == row.accepter -> "accepter"
      true -> nil
    end
  end

  # The chain from the game-row cache, building + backfilling on a cold cache
  # (the ~10s scrypt walk is pre-warmed on BackgammonView mount and cached at
  # accept).
  defp chain_for(row, role, socket) do
    case Chain.cache_get(row, role) do
      chain when is_list(chain) ->
        chain

      _ ->
        with {:ok, gid} <- Base.decode16(row.game_id, case: :lower) do
          chain = chain_seed(socket, gid, role) |> Chain.generate()

          Chain.cache_put(row.game_id, role, chain)
          chain
        end
    end
  end

  # Append a play-log entry (roll or turn) on the author's own facet of the
  # game's derived log; LogWriter refolds the challenges index after the write.
  defp write_play_entry(socket, row, entry) do
    with {:ok, gid} <- Base.decode16(row.game_id, case: :lower) do
      base =
        Game.game_base(
          row.challenger,
          row.accepter,
          gid,
          QuaggaDef.family_tag(:backgammon)
        )

      log_id = Game.game_log_id(base, socket.assigns.facet_id)

      LogWriter.new_entry(Map.put(entry, "log_id", Integer.to_string(log_id)), socket)
    end
  end

  defp menu_entry("none"), do: :none
  defp menu_entry("all"), do: :all
  defp menu_entry(entry) when is_binary(entry), do: String.to_existing_atom(entry)

  # A blank target means an open challenge; a key directs it to that player
  # only. Challenging yourself is meaningless, so it is ignored and no log
  # gets written.
  defp challenge_target(params) do
    case params |> Map.get("to", "") |> String.trim() do
      "" -> nil
      whom -> whom
    end
  end

  @prefs_keys Preferences.keys()
  defp do_prefs([]), do: :ok

  defp do_prefs([{key, val} | rest]) when key in @prefs_keys do
    Preferences.set(key, val)
    do_prefs(rest)
  end

  defp do_prefs([_ | rest]), do: do_prefs(rest)

  defp accepted_log_names do
    QuaggaDef.log_defs()
    |> Enum.filter(fn {_k, v} -> Preferences.accept_log_name?(v.name) end)
    |> Enum.map(fn {_k, v} -> v.name end)
    |> MapSet.new()
  end

  defp state_set(socket, from_caller) when is_map(from_caller),
    do: state_set(socket, from_caller, [])

  defp state_set(socket, _from_caller), do: socket

  defp state_set(socket, from_caller, opts) when is_map(from_caller) do
    full_socket = assign(socket, from_caller)
    do_prefs(from_caller |> Map.to_list())
    state = full_socket.assigns
    clump_id = state.clump_id

    {si, shash} =
      if opts[:skip_hash] do
        {Baobab.stored_info(clump_id), state.store_hash}
      else
        shash = Baobab.Persistence.content_hash(clump_id)

        case state.store_hash do
          ^shash ->
            {state.store, shash}

          _ ->
            Catenary.Indices.update()
            {Baobab.stored_info(clump_id), shash}
        end
      end

    assign(full_socket,
      aliases: Catenary.alias_state(),
      profile_items: Catenary.profile_items_state(),
      indexing: Catenary.Indices.status(),
      shown_hash: Preferences.shown_hash(),
      has_unshown: has_unshown_entries?(clump_id),
      has_identity_unshown_mentions: has_identity_unshown_mentions?(state.identity),
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

  # Manual connect attempt lifecycle: :connecting -> :connected | :failed ->
  # cleaned up. Establishment and disconnection are driven in near-realtime by
  # Catenary.ConnectionMonitor's :connections_changed broadcasts (see
  # reconcile_manual/1); the timeout only exists because Baby.connect gives no
  # synchronous failure signal, so an attempt that never establishes is declared
  # failed after @manual_connect_timeout.
  defp start_manual_connect(socket, host, port) do
    target = {host, port}
    cancel_manual_timers(socket, target)
    prior = socket.assigns[:manual][target]
    attempt = ((prior && prior.attempt) || 0) + 1

    # If the peer is already connected there will be no registry change to push
    # a :connections_changed broadcast, so start it as :connected right away.
    if manual_connected_in?(Baby.Connection.Registry.active(), host, port) do
      {:noreply, put_manual_entry(socket, target, %{state: :connected, attempt: attempt})}
    else
      timeout =
        Process.send_after(
          self(),
          {:manual_connect_timeout, target, attempt},
          @manual_connect_timeout
        )

      entry = %{state: :connecting, attempt: attempt, timeout_timer: timeout}
      {:noreply, put_manual_entry(socket, target, entry)}
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

  defp remove_manual_entry(socket, target) do
    state_set(socket, %{manual: Map.delete(socket.assigns[:manual] || %{}, target)})
  end

  # Reconcile the manual-peer list against the live connection registry: an
  # entry that is still :connecting is promoted to :connected once its peer
  # appears, and a :connected entry whose connection has dropped is removed
  # (cleanup happens here, in realtime, as soon as the monitor sees the change).
  # :failed entries linger only until @manual_failed_grace (see the timeout and
  # :manual_cleanup handlers).
  defp reconcile_manual(socket) do
    active = Baby.Connection.Registry.active()

    Enum.reduce(socket.assigns[:manual] || %{}, %{}, fn {target, entry}, acc ->
      reconcile_target(active, target, entry, acc)
    end)
  end

  defp reconcile_target(active, {host, port} = target, %{state: :connecting} = entry, acc) do
    if manual_connected_in?(active, host, port) do
      if t = Map.get(entry, :timeout_timer), do: Process.cancel_timer(t)
      Map.put(acc, target, %{entry | state: :connected})
    else
      Map.put(acc, target, entry)
    end
  end

  defp reconcile_target(active, {host, port} = target, %{state: :connected} = entry, acc) do
    if manual_connected_in?(active, host, port) do
      Map.put(acc, target, entry)
    else
      acc
    end
  end

  defp reconcile_target(_active, target, entry, acc) do
    Map.put(acc, target, entry)
  end

  # Stop the timers of any previous attempt for this target only; attempts
  # against other targets continue undisturbed.
  defp cancel_manual_timers(socket, target) do
    case socket.assigns[:manual][target] do
      nil ->
        :ok

      entry ->
        if t = Map.get(entry, :timeout_timer), do: Process.cancel_timer(t)
        if t = Map.get(entry, :cleanup_timer), do: Process.cancel_timer(t)
    end
  end

  # Whether a manually entered peer already has an active connection, so the UI
  # can mirror the explorer's connected/attempting-sync indicators. Both address
  # families are tried, since either may be in use.
  defp manual_connected_in?(active, host, port) when is_binary(host) and is_integer(port) do
    charlist = String.to_charlist(host)

    Enum.any?([:inet, :inet6], fn family ->
      case :inet.getaddr(charlist, family) do
        {:ok, addr} -> {addr, port} in active
        _ -> false
      end
    end)
  end

  defp manual_connected_in?(_, _, _), do: false

  defp trigger_mdns_browse(socket) do
    clump_id = socket.assigns.clump_id

    parent = self()

    Task.start(fn ->
      peers = Baby.Mdns.browse() |> Enum.filter(fn p -> p.txt["clump_id"] == clump_id end)
      send(parent, {:mdns_peers, peers})
    end)

    socket
  end

  # Derive a provably-fair chain seed from the logged-in identity's secret and
  # the game context, so the chain is recoverable from the logs alone.
  # Game IDs are always the raw 32-byte binary here; the hex string form only
  # exists in the UI layer and is decoded before this is called.
  defp chain_seed(socket, game_id, role) when byte_size(game_id) == 32 do
    secret =
      case Catenary.id_for_key(socket.assigns.identity) do
        name when is_binary(name) -> Baobab.Identity.key(name, :secret)
        _ -> :error
      end

    Chain.seed_for(secret, game_id, role)
  end

  # Publish a challenge entry on log 777. When `to` is a base62 key the game
  # is addressed to that player only; otherwise it is open to any accepter.
  defp publish_challenge(family, to, socket) do
    with {tag, ""} <- Integer.parse(family),
         true <- tag >= 0 and tag <= 255,
         # A self-directed challenge would sit unacceptably in your own
         # "To you" list forever; refuse to write it.
         false <- to == socket.assigns.identity do
      game_id = :crypto.strong_rand_bytes(32)

      chain_commit =
        if tag == QuaggaDef.family_tag(:backgammon) do
          chain_seed(socket, game_id, "challenger")
          |> Chain.generate()
          |> Chain.commit()
          |> Base.encode16(case: :lower)
        end

      challenge =
        %{
          "log_id" => "777",
          "type" => "challenge",
          "game_id" => game_id,
          "family" => tag,
          "player" => socket.assigns.identity,
          "role" => "challenger",
          "chain_spec" => Chain.spec(),
          "chain_commit" => chain_commit
        }

      challenge =
        case to do
          nil -> challenge
          _ -> Map.put(challenge, "to", to)
        end

      LogWriter.new_entry(challenge, socket)

      {:noreply, state_set(socket, %{view: :challenges, entry: :all})}
    else
      _ -> {:noreply, socket}
    end
  end

  # Second write on accept: the accepter's kickoff entry on the game's play
  # log (a derived log), so the play stream reconstructs on its own. It lands
  # on the accepter's own device facet and carries the full game context
  # (players, chain spec/commits, the accepter's first reveal, base + log id).
  defp publish_play_entry(socket, gid, tag, challenger, chain_commit, reveal, params) do
    with challenger_commit when is_binary(challenger_commit) and challenger_commit != "" <-
           Map.get(params, "challenge_commit"),
         {:ok, cc} <- Base.decode16(challenger_commit, case: :lower) do
      game_base =
        Game.game_base(challenger, socket.assigns.identity, gid, tag)

      game_log_id = Game.game_log_id(game_base, socket.assigns.facet_id)

      play =
        Game.play_entry(
          socket.assigns.identity,
          gid,
          tag,
          challenger,
          game_base,
          game_log_id: game_log_id,
          chain_commit: unhex(chain_commit),
          challenger_commit: cc,
          reveal: unhex(reveal),
          chain_spec: Chain.spec()
        )

      LogWriter.new_entry(Map.put(play, "log_id", Integer.to_string(game_log_id)), socket)
    else
      _ -> :ok
    end
  end

  defp unhex(nil), do: nil
  defp unhex(hex), do: Base.decode16!(hex, case: :lower)
end
