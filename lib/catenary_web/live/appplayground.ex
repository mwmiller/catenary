defmodule Catenary.Live.AppPlayground do
  @moduledoc """
  LiveComponent rendering the app playground: the draft editor over the pane
  the draft runs in.

  The component keeps no state of its own beyond the app scope it answers
  host calls with. The draft lives on the parent LiveView so that leaving the
  view and coming back does not lose what was typed, which is also why the
  editor reports its document up rather than holding it.

  The editor mount point is `phx-update="ignore"` because the `CodeEditor`
  hook writes DOM that the next LiveView patch must not reconcile away, and
  it carries the draft as `data-value` only so the hook has something to
  start from when it mounts. The run pane is ignored for the same reason: the
  `AppRunner` hook owns the worker, the print log and the view it draws.

  Host calls from a scratch run are answered against a fixed scope — the
  current clump, the current identity, and a slug that means "not a real
  app" — because a draft has no listing to belong to. That keeps
  `storage_get`/`storage_set` working while the author iterates, and keeps
  the keys out of any published app's space. The same scope is what a
  `publish` derives its channel from (§6), which is why the facet this
  device writes on comes in with the rest of it.
  """
  use CatenaryWeb, :live_component

  alias Catenary.{AppHost, AppPublish, AppWire}

  @scratch_slug "playground"

  # What a new draft starts from: a module that round trips through the
  # host's storage, publishes one entry to its own channel and reads that
  # channel back — the ABI's rules in the order they bite, before the DSL
  # compiler (step 6) gives the buffer its own language.
  @starter """
  # The playground's own language. Press Run: this compiles to wasm on the
  # server, right here, with no toolchain of your own.
  #
  # Handlers are the messages a host can deliver. Everything else is data:
  # print pushes a line to the trace, render hands the pane a widget tree,
  # draw paints on the canvas that view declared, want asks the host a
  # question whose answer arrives on the data handler that named it, and
  # publish appends a typed entry to the channel this app's own name
  # derives — the host decides where from, never the entry. channel reads
  # that same name back: every installation derives the same base, so
  # where messages appear is agreed by derivation, not remembered.

  on init:
    print("hello from the DSL")
    want "set_done" = storage_set(key: "greeting", value: 41)
    publish(type: "note", text: "the DSL starter says hello")
    want "feed" = channel(limit: 5)
    render(col(text("widgets"), row(text("a"), text("b")), canvas(160, 96)))

  # The data handlers chain: storing reports itself by fetching, and
  # fetching stops. Every want answers on the label it named, and the
  # handler bound to that label receives the reply as a decoded value —
  # here the page of entries the channel holds, newest published first.
  on data("feed", r):
    print("channel entries: " + show(len(r)))

  on data("set_done", r):
    print("stored: " + show(r))
    want "get_done" = storage_get(key: "greeting")

  on data("get_done", r):
    print("fetched: " + show(r))

  on ui(e):
    draw[fill_rect(x: 8, y: 8, w: 48, h: 32, c: "#22c55e")]
    print("tapped")

  on err(m):
    print("host error: " + m)
  """

  @doc """
  The buffer a brand-new draft opens with. The parent LiveView reads it once
  at mount; after that the draft is whatever the author typed.
  """
  @spec starter_source() :: String.t()
  def starter_source, do: @starter

  @impl true
  def update(
        %{clump_id: clump_id, identity: identity, facet_id: facet_id} = assigns,
        socket
      ) do
    app = AppHost.app(clump_id, identity, @scratch_slug)
    scope = %{app: app, identity: identity, facet_id: facet_id}
    {:ok, assign(socket, assigns |> Map.put(:app, app) |> Map.put(:scope, scope))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="playground-explore-wrap" class="content-wrap">
      <div class="flex flex-col gap-4">
        <h1 class="text-lg font-semibold text-slate-800 dark:text-slate-100">Playground</h1>
        <div
          id="playground-editor"
          phx-hook="CodeEditor"
          phx-update="ignore"
          data-value={@source}
          class="h-[45vh] overflow-hidden rounded-lg border border-slate-200 dark:border-slate-700"
        >
        </div>
        <div
          id="playground-pane"
          phx-hook="AppRunner"
          phx-update="ignore"
          phx-target={@myself}
          data-worker-src={~p"/assets/app_worker.js"}
          data-trace="1"
          class="rounded-lg border border-slate-200 dark:border-slate-700 p-3 flex flex-col gap-2"
        >
          <p id="app-status" class="text-sm text-slate-400 dark:text-slate-600">
            Nothing running.
          </p>
          <pre
            id="app-print"
            class="h-24 shrink-0 overflow-y-auto whitespace-pre-wrap text-xs font-mono text-slate-600 dark:text-slate-300"
          ></pre>
          <div
            id="app-view"
            class="hidden whitespace-pre-wrap text-sm font-mono text-slate-700 dark:text-slate-200"
          >
          </div>
        </div>
        <p class="text-sm text-slate-600 dark:text-slate-400">
          The store fixture picker is not built. Run compiles the buffer — DSL by default, WAT
          when the buffer opens with a module — and starts it; a buffer that does not compile
          reports its diagnostic on the status line and in the trace. A run that publishes (the
          starter does) appends to this identity's own playground channel. ⇪ opens the publish
          panel, which compiles the buffer as it stands and writes the artifact, its source, a
          manifest and a listing to this identity's own app logs — the trace line names the
          manifest revision and the artifact's hash. ⇥ on the right rail — or a file dropped on
          the pane — runs a .wasm instead, gated on it instantiating here. Everything that
          happens lands on the left, in one trace: where each entry went, and what the host
          refused and why.
        </p>
      </div>
    </div>
    """
  end

  # The reply goes back to whichever hook made the call, so one round trip is
  # one promise resolution: the worker never has to correlate an id by hand.
  @impl true
  def handle_event("app-want", %{"op" => op, "args" => args}, socket) do
    {:reply, AppWire.request(socket.assigns.app, op, args), socket}
  end

  def handle_event("app-want", _params, socket) do
    {:reply, AppWire.request(socket.assigns.app, nil, nil), socket}
  end

  # A publish is the same round trip with nothing to answer back on: the
  # entry goes up wrapped the way a want's arguments are, and the scope it
  # is judged against is this component's, so a draft can only ever append
  # to the channel its own (identity, "playground") derives (§6).
  def handle_event("app-publish", %{"entry" => entry}, socket) do
    {:reply, AppPublish.publish(socket.assigns.scope, entry), socket}
  end

  def handle_event("app-publish", _params, socket) do
    {:reply, %{"ok" => false, "error" => "bad_args"}, socket}
  end
end
