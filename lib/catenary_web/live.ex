defmodule CatenaryWeb.Live do
  @moduledoc """
  Catenary's top-level Phoenix LiveView: mounting assigns, routing between views, and wiring the entry/navigation card components.
  """
  use CatenaryWeb, :live_view
  require Logger

  alias Catenary.{
    Display,
    Games.Backgammon.Chain,
    Games.Backgammon.Game,
    IndexWorker.Challenges,
    Live.AppPlayground,
    LogWriter,
    Navigation,
    Preferences
  }

  # The control log the challenge forms publish to; the same value
  # LogWriter's challenge clauses match on.
  @challenge_log_id Integer.to_string(QuaggaDef.control_log(:backgammon))

  # What one playground draft may hold in socket state. An authoring buffer,
  # not a file format — the publish path re-checks against the real artifact
  # cap — so this only bounds what a keystroke may carry up the socket.
  @max_source_bytes 256 * 1024

  # How much of a run's trace the LiveView keeps. The hook batches and trims
  # before it sends, and this trims again, because the trace is held in
  # assigns for the life of the session and a module that prints in a loop
  # must not be able to grow it without bound.
  @trace_limit 200

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
         source: AppPlayground.starter_source(),
         trace: [],
         trace_at: 0,
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

  def render(%{view: :listings} = assigns) do
    ~H"""
    <.three_column_layout {assigns}>
      <.live_component
        module={Catenary.Live.ListingsExplorer}
        id={:listings}
        index_version={@index_version}
        entry={:all}
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

  def render(%{view: :app, entry: {:app, {pk, slug}}} = assigns) do
    assigns = assign(assigns, pk: pk, slug: slug)

    ~H"""
    <.three_column_layout {assigns}>
      <.live_component
        module={Catenary.Live.AppViewer}
        id={:app}
        index_version={@index_version}
        pk={@pk}
        slug={@slug}
        clump_id={@clump_id}
        aliases={@aliases}
        entry={@entry}
      />
    </.three_column_layout>
    """
  end

  # The app view only means anything with an app to run. Landing here from a
  # saved entry whose listing has since delisted gets a plain message rather
  # than a function-clause crash on the whole LiveView.
  def render(%{view: :app} = assigns) do
    ~H"""
    <.three_column_layout {assigns}>
      <div id="app-explore-wrap" class="content-wrap">
        <p class="text-sm text-slate-400 dark:text-slate-600">No app open.</p>
      </div>
    </.three_column_layout>
    """
  end

  # The playground is authoring, not indexing, so it has no button on the
  # explorebar strip — that strip is the views gated on a log name and reads
  # as what is indexed. It arrives from the listings header's *New app*
  # action instead, and `entry: :all` is the blank draft: there is no app open
  # here yet, only the pane that will hold one.
  def render(%{view: :playground} = assigns) do
    ~H"""
    <.three_column_layout {assigns}>
      <.live_component
        module={Catenary.Live.AppPlayground}
        id={:playground}
        source={@source}
        clump_id={@clump_id}
        identity={@identity}
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
        <!-- Left: settings + clump + identity -->
        <div class="flex items-center gap-1 shrink-0 text-sm font-mono">
          <button
            phx-click="prefs"
            title="Settings"
            aria-label="Settings"
            aria-current={aria_current(@view, :prefs)}
            class={[
              if(@view == :prefs, do: "bg-amber-100 dark:bg-amber-900/40"),
              "flex items-center text-base leading-none rounded-md px-1.5 py-1 text-slate-600 dark:text-slate-400 hover:text-amber-700 dark:hover:text-amber-400 transition-colors"
            ]}
          >⚙</button>
          <span
            class="text-slate-500 dark:text-slate-400 select-none"
            title="Clump"
          >{@clump_id}</span>
          <span class="text-slate-500 dark:text-slate-400 select-none">/</span>
          <button
            value="origin"
            phx-click="nav"
            title="Your profile"
            aria-label="Your profile"
            aria-current={if(profile_current?(@view, @entry, @identity), do: "page")}
            class={[
              if(profile_current?(@view, @entry, @identity),
                do: "bg-amber-100 dark:bg-amber-900/40"
              ),
              "relative flex items-center gap-1 rounded-md px-1.5 py-0.5 hover:text-amber-700 dark:hover:text-amber-400 transition-colors"
            ]}
          >
            {Display.scaled_avatar(@identity, 2) |> Phoenix.HTML.raw()}
            <span class="truncate">{Display.linked_author(@identity, @aliases)}</span>
            <span :if={@has_identity_unshown_mentions} class="btn-icon-badge" aria-hidden="true"></span>
          </button>
        </div>

        <!-- Center: nav buttons -->
        <div class="flex items-center gap-0.5 overflow-x-auto flex-1 justify-center min-w-0 scrollbar-hide">
          <button
            class={stack_color(@entry_back)}
            phx-click="nav-backward"
            title="Back"
            aria-label="Back"
            disabled={@entry_back == []}
          >⤶</button>
          <button
            :if={Preferences.accept_log_name?(:challenge)}
            value="challenges"
            phx-click="toview"
            title="Challenges"
            aria-label="Challenges"
            aria-current={aria_current(@view, :challenges)}
            class={view_btn_cls(@view, :challenges)}
          >⚄</button>
          <button
            :if={Preferences.accept_log_name?(:listing)}
            value="listings"
            phx-click="toview"
            title="Listings"
            aria-label="Listings"
            aria-current={aria_current(@view, :listings)}
            class={view_btn_cls(@view, :listings)}
          >⬡</button>
          <button
            :if={Preferences.accept_log_name?(:tag)}
            value="tags"
            phx-click="toview"
            title="Tags"
            aria-label="Tags"
            aria-current={aria_current(@view, :tags)}
            class={view_btn_cls(@view, :tags)}
          >#</button>
          <button
            :if={
              Preferences.accept_log_name?(:gif) or Preferences.accept_log_name?(:png) or
                Preferences.accept_log_name?(:jpeg)
            }
            value="images"
            phx-click="toview"
            title="Images"
            aria-label="Images"
            aria-current={aria_current(@view, :images)}
            class={view_btn_cls(@view, :images)}
          >▣</button>
          <button
            :if={Preferences.accept_log_name?(:react)}
            value="reactions"
            phx-click="toview"
            title="Reactions"
            aria-label="Reactions"
            aria-current={aria_current(@view, :reactions)}
            class={view_btn_cls(@view, :reactions)}
          >♥</button>
          <button
            value="unshown"
            phx-click="toview"
            title="Unshown"
            aria-label="Unshown"
            aria-current={aria_current(@view, :unshown)}
            class={view_btn_cls(@view, :unshown)}
          >◎<span :if={@has_unshown} class="btn-icon-badge" aria-hidden="true"></span></button>
          <button
            :if={Preferences.accept_log_name?(:alias)}
            value="aliases"
            phx-click="toview"
            title="Aliases"
            aria-label="Aliases"
            aria-current={aria_current(@view, :aliases)}
            class={view_btn_cls(@view, :aliases)}
          >~</button>
          <button
            :if={Preferences.accept_log_name?(:oasis)}
            value="oases"
            phx-click="toview"
            title="Peers"
            aria-label="Peers"
            aria-current={aria_current(@view, :oases)}
            class={view_btn_cls(@view, :oases)}
          >⇆</button>
          <button
            class={stack_color(@entry_fore)}
            phx-click="nav-forward"
            title="Forward"
            aria-label="Forward"
            disabled={@entry_fore == []}
          >⤷</button>
        </div>

        <!-- Right: index status, then the reindex control. Siblings rather
             than one strip: the indicators are a read-out and the button is
             an action, so they must not share a background. -->
        <div class="shrink-0 flex items-center gap-1.5">
          <.live_component
            module={Catenary.Live.IndexStatus}
            id={:indices}
            index_version={@index_version}
            indexing={@indexing}
          />
          <button
            type="button"
            phx-click="reindex"
            phx-disable-with="⟳"
            title="Reindex"
            aria-label="Reindex"
            class="shrink-0 rounded-md border border-slate-300 dark:border-slate-600 px-2 py-1 text-sm leading-none text-slate-600 dark:text-slate-300 transition-colors hover:border-amber-500 hover:bg-slate-100 hover:text-amber-700 dark:hover:border-amber-400 dark:hover:bg-slate-800 dark:hover:text-amber-400"
          ><span aria-hidden="true">⟳</span></button>
        </div>
      </div>
    </div>
    """
  end

  def stack_color([]) do
    "btn-icon disabled:opacity-40 disabled:cursor-default disabled:hover:bg-transparent"
  end

  def stack_color(_), do: "btn-icon"

  # Marks the explorebar button for the view currently on screen, so the
  # active destination is visible as well as announced.
  def aria_current(view, view), do: "page"
  def aria_current(_, _), do: nil

  def view_btn_cls(view, view), do: "btn-icon btn-icon-current"
  def view_btn_cls(_, _), do: "btn-icon"

  def profile_current?(view, entry, identity),
    do: view == :entries and entry == {:profile, identity}

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

  # The playground is an authoring workspace, not a feed screen: the compose
  # and challenge triggers post to logs, which is not what is happening here.
  # Swapping the rail is a render decision only — every assign `Navigation`
  # reads (history stacks, the open compose panel, the current entry) belongs to
  # this LiveView, so the component draws again unchanged on the way back.
  defp activitybar(%{view: :playground} = assigns) do
    ~H"""
    <div class="mt-5 min-h-[400px]">
      <.live_component module={Catenary.Live.PlaygroundNav} id={:playground_nav} />
    </div>
    """
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

  # Prev/next author and entry walk a timeline, and a draft has none: following
  # these would push entries onto the history stacks for a screen that ignores
  # them. The rail itself stays — same width, same height, different tools —
  # so the three-column layout does not collapse and shift the editor when the
  # author leaves the playground and comes back. The explorebar's Back and
  # Forward stay live too: that is the author's own way home.
  defp timeline_nav(%{view: :playground} = assigns) do
    ~H"""
    <.live_component
      module={Catenary.Live.PlaygroundTimeline}
      id={:playground_timeline}
      trace={@trace}
      trace_at={@trace_at}
    />
    """
  end

  defp timeline_nav(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-1 pt-4">
      <button
        value="prev-author"
        phx-click="nav"
        title="Prev author"
        aria-label="Previous author"
        class="btn-icon"
      >↥</button>
      <button
        value="prev-entry"
        phx-click="nav"
        title="Prev entry"
        aria-label="Previous entry"
        class="btn-icon"
      >⇜</button>
      <button
        value="next-entry"
        phx-click="nav"
        title="Next entry"
        aria-label="Next entry"
        class="btn-icon"
      >⇝</button>
      <button
        value="next-author"
        phx-click="nav"
        title="Next author"
        aria-label="Next author"
        class="btn-icon"
      >↧</button>
    </div>
    """
  end

  # Compiling belongs here rather than in the rail button that asks for it:
  # the draft is this LiveView's assign, and the module has to reach the pane
  # as one push either way. A failure is a trace entry and a status line, not
  # an exception — a buffer that does not compile is the ordinary case while
  # it is being written.
  def handle_info(:playground_run, socket) do
    socket = assign(socket, trace: [], trace_at: 0)

    case compile_wat(socket.assigns.source) do
      {:ok, wasm} ->
        {:noreply, push_event(socket, "app-run", %{"wasm" => Base.encode64(wasm)})}

      {:error, message} ->
        socket = record_trace(socket, [%{"kind" => "compile", "detail" => message}])
        {:noreply, push_event(socket, "app-run", %{"error" => message})}
    end
  end

  def handle_info(:playground_stop, socket) do
    {:noreply, push_event(socket, "app-stop", %{})}
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

  # The playground draft lives on the LiveView rather than in the
  # AppPlayground component: navigating away destroys the component, and an
  # editor buffer that empties when you click ⬡ is not an editor buffer. The
  # CodeEditor hook debounces, so this is one message per burst of typing
  # rather than one per keystroke.
  def handle_event("playground-source", %{"value" => value}, socket)
      when is_binary(value) do
    {:noreply, assign(socket, source: String.slice(value, 0, @max_source_bytes))}
  end

  # The run's history, batched by the hook so a chatty module is one message
  # per flush rather than one per line, and the cursor over it. Both live on
  # the LiveView because that is what the left rail renders from.
  def handle_event("app-trace", %{"entries" => entries}, socket) when is_list(entries) do
    {:noreply, record_trace(socket, entries)}
  end

  def handle_event("trace-step", %{"value" => step}, socket) do
    last = max(length(socket.assigns.trace) - 1, 0)

    at =
      case step do
        "prev" -> max(socket.assigns.trace_at - 1, 0)
        "next" -> min(socket.assigns.trace_at + 1, last)
        _ -> socket.assigns.trace_at
      end

    {:noreply, assign(socket, trace_at: at)}
  end

  # Settings (⚙ in the explorebar) are a mode, not a content view: switching
  # to them goes through state_set directly so they never appear on the
  # back/forward history stack.
  def handle_event("prefs", _, socket) do
    {:noreply, state_set(socket, %{view: :prefs, entry: :all})}
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
    closing? = socket.assigns.extra_nav == tog
    socket = state_set(socket, %{extra_nav: if(closing?, do: :none, else: tog)})

    {:noreply, if(closing?, do: focus_compose_trigger(socket, tog), else: socket)}
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
          "log_id" => @challenge_log_id,
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
          %{"log_id" => @challenge_log_id, "type" => "withdraw", "game_id" => gid},
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

  # A submit is dropped when it repeats the previous publish inside the
  # debounce window or carries no reply body (repeat_publish?/4 and
  # blank_reply?/1), and a publish that does go through closes the compose
  # panel.
  def handle_event("new-entry", values, socket) do
    now = System.monotonic_time(:millisecond)
    repeat? = repeat_publish?(socket.assigns[:last_publish], values, now, publish_debounce_ms())

    if repeat? or blank_reply?(values) do
      {:noreply, socket}
    else
      closed = socket.assigns.extra_nav
      entry = LogWriter.new_entry(values, socket)
      socket = assign(socket, last_publish: {:erlang.phash2(values), now})
      moved = Navigation.move_to("new", %{view: :entries, entry: entry}, socket.assigns)

      # Publishing closes the compose panel. What stays open is re-rendered
      # against the entry just created — with an empty body and a ref to the
      # reply that was only just posted — so one more click on the re-enabled
      # button would publish that. Focus goes back to the trigger that opened
      # it, exactly as it does for Escape.
      socket = state_set(socket, Map.put(moved, :extra_nav, :none))

      {:noreply, if(closed == :none, do: socket, else: focus_compose_trigger(socket, closed))}
    end
  end

  def handle_event("accept-change", values, socket) do
    all_log_names =
      QuaggaDef.log_defs() |> Enum.map(fn {_k, v} -> v.name end)

    checked =
      all_log_names
      |> Enum.filter(fn name -> Map.has_key?(values, "log_name-#{name}") end)
      |> MapSet.new()

    {:noreply, assign(socket, accepted_logs: checked)}
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

  # Preferences via the native menu: same mode (not navigation-history)
  # treatment as the ⚙ explorebar button.
  def handle_event("menu", %{"view" => "prefs"}, socket) do
    {:noreply, state_set(socket, %{view: :prefs, entry: :none})}
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

  # Escape dismisses the compose panel, mirroring the ⍟ close button in the
  # activity bar. Renders as a no-op when no panel is open, since :none is
  # already the resting state.
  def handle_event("escape", _, socket) do
    closing = socket.assigns.extra_nav
    socket = state_set(socket, %{extra_nav: :none})

    {:noreply, if(closing == :none, do: socket, else: focus_compose_trigger(socket, closing))}
  end

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

  # Closing a compose panel tears out the markup that had focus, which drops a
  # keyboard user back on <body> with no idea where they were; Tab then restarts
  # from the top of the page. Hand focus back to the trigger that opened it.
  #
  # Handed over as an id rather than a ref because the trigger lives in a
  # sibling LiveComponent, and it may legitimately not be on screen at all: a
  # panel can be forced open by the entry being viewed (see
  # `Navigation.force_extra_nav/2`) with no trigger rendered, so the client side
  # treats a missing element as a no-op.
  defp focus_compose_trigger(socket, which) do
    push_event(socket, "focus-compose-trigger", %{id: "compose-trigger-#{which}"})
  end

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

  # A publish is debounced against a double-click. `phx-disable-with` only
  # covers the round trip, so the button is live again the moment the reply is
  # acked, and the re-rendered panel would hand the second click an empty form
  # to post. Fingerprinting the payload keeps a deliberate second post of
  # *different* content from ever being swallowed: only a repeat of the exact
  # same values inside the window is treated as an accident.
  @publish_debounce_ms 2_000

  # The window is a wall-clock span, and the repeat-publish test on CI renders
  # slowly enough to outlast the two seconds a double-click could ever take.
  # Tests therefore set their own span, which is harmless: `last_publish` is
  # socket state, and every test opens its own LiveView.
  defp publish_debounce_ms,
    do: Application.get_env(:catenary, :publish_debounce_ms, @publish_debounce_ms)

  @doc false
  def repeat_publish?({fingerprint, at}, values, now, window_ms),
    do: fingerprint == :erlang.phash2(values) and now - at < window_ms

  def repeat_publish?(_last_publish, _values, _now, _window_ms), do: false

  # A reply carries its content in the body; the title is prefilled from the
  # entry being answered, so an empty body is never a deliberate reply. It is
  # what an accidental Enter in the title field (or the second half of a
  # double-click) publishes.
  defp blank_reply?(%{"log_id" => "533", "body" => body}) when is_binary(body),
    do: String.trim(body) == ""

  defp blank_reply?(%{"log_id" => "533"}), do: true

  defp blank_reply?(_values), do: false

  # The alias index folds the active identity's log and no other, so the map
  # it holds belongs to whichever identity was active when it ran. Switching
  # identities has to fold the new log before any view reads names out of the
  # old map. The worker broadcasts :index_change when the pass finishes, which
  # is what comes back through here with the fresh map in the assigns.
  defp maybe_reindex_aliases(socket, %{identity: who}) when is_binary(who) do
    if Map.has_key?(socket.assigns, :identity) and socket.assigns.identity != who do
      Catenary.Indices.update([:aliases])
    end

    :ok
  end

  defp maybe_reindex_aliases(_socket, _from_caller), do: :ok

  # WAT to wasm for the playground's Run. watusi raises on a buffer it cannot
  # parse, and a buffer that does not parse is the ordinary case while it is
  # being written rather than a crash of the LiveView process, so the raise
  # is the error channel.
  defp compile_wat(source) when is_binary(source) do
    {:ok, Watusi.to_wasm(source)}
  rescue
    error -> {:error, Exception.message(error)}
  end

  # Append to the run's trace, keeping the newest @trace_limit entries and
  # moving the cursor to the tail: a fresh trace is read from the end, the
  # way a print log is. Malformed entries are dropped rather than rendered —
  # the list comes off the socket, so it is data the LiveView did not write.
  defp record_trace(socket, entries) do
    clean =
      for %{"kind" => kind, "detail" => detail} <- entries,
          is_binary(kind),
          is_binary(detail) do
        %{"kind" => kind, "detail" => String.slice(detail, 0, 400)}
      end

    trace = Enum.slice(socket.assigns.trace ++ clean, -@trace_limit, @trace_limit)
    assign(socket, trace: trace, trace_at: max(length(trace) - 1, 0))
  end

  defp state_set(socket, from_caller) when is_map(from_caller),
    do: state_set(socket, from_caller, [])

  defp state_set(socket, _from_caller), do: socket

  defp state_set(socket, from_caller, opts) when is_map(from_caller) do
    full_socket = assign(socket, from_caller)
    do_prefs(from_caller |> Map.to_list())
    maybe_reindex_aliases(socket, from_caller)

    # A compose panel outlives the screen that offered it whenever navigation
    # moves somewhere its trigger is not rendered (a reply on the tags screen,
    # an alias on a tag), and the component would then draw an empty frame.
    # Drop it here, where view and entry change, rather than only rendering
    # around it in the component: `toggle-` reads this assign to decide
    # whether a trigger opens or closes.
    full_socket =
      assign(full_socket,
        extra_nav:
          Catenary.Live.Navigation.resolve_extra_nav(
            full_socket.assigns[:extra_nav],
            full_socket.assigns.view,
            full_socket.assigns.entry
          )
      )

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

    shown_hash = Preferences.shown_hash()

    # has_unshown_entries?/1 walks every entry in the clump, and state_set/3
    # runs on every event, so that walk ran on every keystroke and click. It
    # depends on exactly two things, and both already have a change-detection
    # digest in hand here, so re-walk only when one of them actually moved:
    # reuse the last answer when neither did.
    #
    # shown_hash is a blake2b of `Preferences.get(:shown)[clump_id]`, the same
    # set the walk reads (this_clump_shown_set/0, and clump_id here is the
    # `Preferences.get(:clump_id)` captured at mount). store_hash is the content
    # hash the block above already trusts to decide whether the store changed
    # at all. On the skip_hash path shash is state.store_hash by construction,
    # so an explicit skip correctly reuses the cached answer too.
    has_unshown =
      if state.shown_hash == shown_hash and state.store_hash == shash do
        state.has_unshown
      else
        has_unshown_entries?(clump_id)
      end

    refreshed =
      assign(full_socket,
        aliases: Catenary.alias_state(),
        profile_items: Catenary.profile_items_state(),
        indexing: Catenary.Indices.status(),
        shown_hash: shown_hash,
        has_unshown: has_unshown,
        has_identity_unshown_mentions: has_identity_unshown_mentions?(state.identity),
        store_hash: shash,
        store: si,
        oases: Catenary.oasis_state(),
        # This is a place holder for interesting stats later
        # It is needed to make onboarding less confusing for now
        opened: Baby.Connection.Registry.active() |> Enum.count()
      )

    if connected?(socket) and moved_to_new_content?(socket.assigns, state) do
      push_event(refreshed, "reset-scroll", %{})
    else
      refreshed
    end
  end

  # Each view renders its body inside a stable `.content-wrap` scroll container
  # that LiveView morphs in place, so the browser keeps the old scroll offset
  # across navigation. Advancing from a long entry would otherwise drop you at
  # the bottom of the next one. Detected here rather than in each navigation
  # handler so every path (arrows, timeline nav, tags, back/forward, the native
  # menu, deep links) is covered by the single choke point.
  defp moved_to_new_content?(old, new) do
    {old[:view], old[:entry]} != {new.view, new.entry}
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
          "log_id" => @challenge_log_id,
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

      # Same contract as `new-entry`: a published challenge takes its panel
      # with it, so the re-enabled button cannot publish a second one.
      socket = state_set(socket, %{view: :challenges, entry: :all, extra_nav: :none})
      {:noreply, focus_compose_trigger(socket, :challenge)}
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
