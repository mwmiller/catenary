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
  the keys out of any published app's space.
  """
  use CatenaryWeb, :live_component

  alias Catenary.{AppHost, AppWire}

  @scratch_slug "playground"

  # What a new draft starts from: a two-state module that prints, stores a
  # value through the host, and renders once the reply comes back — the same
  # shape as the harness fixture, so Run has something that actually runs
  # before the DSL compiler (step 6) gives the buffer its own language.
  @starter """
  ;; A two-turn draft, the shape of a run rather than a program worth
  ;; keeping: the first call prints and asks the host to store a value, the
  ;; reply draws a view and prints again.
  ;;
  ;; The ABI is one function. handle receives a pointer and a length, returns
  ;; a pointer, and the length of the answer is read back from address 0 — so
  ;; every reply is a byte range the host slices out of this memory.
  (module
    ;; One page is plenty for a draft. Nothing here is returned by value:
    ;; what handle points at is what the host reads.
    (memory (export "memory") 1)

    ;; Two turns, one flag: 0 on the way in, 1 on the way back. A module with
    ;; more to say would count turns or dispatch on the message instead.
    (global $state (mut i32) (i32.const 0))

    ;; The first answer: CBOR, 74 bytes at address 16 — an array of two
    ;; effects, `print "init"` and `want storage_set` of hello=41 with ref 1.
    (data (i32.const 16) "\\82\\a2\\62\\64\\6f\\65\\70\\72\\69\\6e\\74\\64\\74\\65\\78\\74\\64\\69\\6e\\69\\74\\a4\\64\\61\\72\\67\\73\\a2\\63\\6b\\65\\79\\65\\68\\65\\6c\\6c\\6f\\65\\76\\61\\6c\\75\\65\\18\\29\\62\\64\\6f\\64\\77\\61\\6e\\74\\62\\6f\\70\\6b\\73\\74\\6f\\72\\61\\67\\65\\5f\\73\\65\\74\\63\\72\\65\\66\\01")

    ;; The reply's answer: 131 bytes at address 512 — `render` of a col (a
    ;; text node, a row of two text nodes, a 96x48 canvas), then `print
    ;; "ready"`. A view is plain data; the pane decides how to draw it.
    (data (i32.const 512) "\\82\\a2\\62\\64\\6f\\66\\72\\65\\6e\\64\\65\\72\\64\\76\\69\\65\\77\\a2\\64\\6b\\69\\64\\73\\83\\a2\\61\\73\\65\\72\\65\\61\\64\\79\\61\\74\\64\\74\\65\\78\\74\\a2\\64\\6b\\69\\64\\73\\82\\a2\\61\\73\\69\\68\\65\\6c\\6c\\6f\\2d\\61\\70\\70\\61\\74\\64\\74\\65\\78\\74\\a2\\61\\73\\62\\76\\31\\61\\74\\64\\74\\65\\78\\74\\61\\74\\63\\72\\6f\\77\\a3\\61\\68\\18\\30\\61\\74\\66\\63\\61\\6e\\76\\61\\73\\61\\77\\18\\60\\61\\74\\63\\63\\6f\\6c\\a2\\62\\64\\6f\\65\\70\\72\\69\\6e\\74\\64\\74\\65\\78\\74\\65\\72\\65\\61\\64\\79")

    ;; The host's message sits at $in for $in_len bytes — the reply to the
    ;; storage_set above arrives here too. This draft ignores it: a module
    ;; worth running reads it before deciding what to say next.
    (func (export "handle") (param $in i32) (param $in_len i32) (result i32)
      (if (result i32) (i32.eqz (global.get $state))
        (then
          (global.set $state (i32.const 1))
          ;; length of the answer at address 0, and where it starts
          (i32.store (i32.const 0) (i32.const 74))
          (i32.const 16))
        (else
          (i32.store (i32.const 0) (i32.const 131))
          (i32.const 512)))))
  """

  @doc """
  The buffer a brand-new draft opens with. The parent LiveView reads it once
  at mount; after that the draft is whatever the author typed.
  """
  @spec starter_source() :: String.t()
  def starter_source, do: @starter

  @impl true
  def update(%{clump_id: clump_id, identity: identity} = assigns, socket) do
    app = AppHost.app(clump_id, identity, @scratch_slug)
    {:ok, assign(socket, Map.put(assigns, :app, app))}
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
            class="hidden whitespace-pre-wrap text-xs font-mono text-slate-600 dark:text-slate-300"
          ></pre>
          <div
            id="app-view"
            class="hidden whitespace-pre-wrap text-sm font-mono text-slate-700 dark:text-slate-200"
          >
          </div>
        </div>
        <p class="text-sm text-slate-600 dark:text-slate-400">
          Compile, the publish panel and the store fixture picker are not built. Run compiles the
          buffer as WAT and starts it; ⇥ on the right rail — or a file dropped on the pane — runs a
          .wasm instead, gated on it instantiating here. Both traces land on the left.
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
end
