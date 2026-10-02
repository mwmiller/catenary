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

  # What a new draft starts from: a nine-turn module that batches wants,
  # round trips through the host's storage, asks a log for its head and then
  # puts four reads in one array — the ABI's rules in the order they bite,
  # before the DSL compiler (step 6) gives the buffer its own language.
  @starter """
  ;; A nine-turn draft: what the ABI feels like from the inside.
  ;;
  ;; The ABI is one function. handle receives a pointer and a length, returns
  ;; a pointer, and the length of the answer is read back from address 0 — so
  ;; every reply is a byte range the host slices out of this memory. What
  ;; arrives at $in is the host's message: effects go out as CBOR, replies
  ;; come back as CBOR too, and this module reads the last one.
  (module
    ;; One page is plenty for a draft. Nothing here is returned by value:
    ;; what handle points at is what the host reads.
    (memory (export "memory") 1)

    ;; Turns, counted. 0 is the way in; every delivery after it is one more,
    ;; because the host calls handle once per message and this module decides
    ;; what to say by how many have come before.
    (global $state (mut i32) (i32.const 0))

    ;; Turn 0, 151 bytes at 16: `print "init"` and two wants in the same
    ;; array — storage_set of hello=41 (ref 1) and of a greeting (ref 2).
    ;; Wants in one array are one tick: they reach the host in the order
    ;; written, and their replies come back in that same order.
    (data (i32.const 16) "\\83\\a2\\62\\64\\6f\\65\\70\\72\\69\\6e\\74\\64\\74\\65\\78\\74\\64\\69\\6e\\69\\74\\a4\\64\\61\\72\\67\\73\\a2\\63\\6b\\65\\79\\65\\68\\65\\6c\\6c\\6f\\65\\76\\61\\6c\\75\\65\\18\\29\\62\\64\\6f\\64\\77\\61\\6e\\74\\62\\6f\\70\\6b\\73\\74\\6f\\72\\61\\67\\65\\5f\\73\\65\\74\\63\\72\\65\\66\\01\\a4\\64\\61\\72\\67\\73\\a2\\63\\6b\\65\\79\\68\\67\\72\\65\\65\\74\\69\\6e\\67\\65\\76\\61\\6c\\75\\65\\76\\68\\69\\20\\66\\72\\6f\\6d\\20\\74\\68\\65\\20\\70\\6c\\61\\79\\67\\72\\6f\\75\\6e\\64\\62\\64\\6f\\64\\77\\61\\6e\\74\\62\\6f\\70\\6b\\73\\74\\6f\\72\\61\\67\\65\\5f\\73\\65\\74\\63\\72\\65\\66\\02")

    ;; Turn 1, the reply to ref 1, 74 bytes at 512: a print and storage_get of
    ;; hello (ref 3) — asking for what turn 0 put away.
    (data (i32.const 512) "\\82\\a2\\62\\64\\6f\\65\\70\\72\\69\\6e\\74\\64\\74\\65\\78\\74\\6c\\68\\65\\6c\\6c\\6f\\20\\73\\74\\6f\\72\\65\\64\\a4\\64\\61\\72\\67\\73\\a1\\63\\6b\\65\\79\\65\\68\\65\\6c\\6c\\6f\\62\\64\\6f\\64\\77\\61\\6e\\74\\62\\6f\\70\\6b\\73\\74\\6f\\72\\61\\67\\65\\5f\\67\\65\\74\\63\\72\\65\\66\\03")

    ;; Turn 2, the reply to ref 2, 74 bytes at 1024: a print and log_head of
    ;; 2777, the control log clumps name `listing` — what has been written to
    ;; it, on the key that wrote it, since `author` defaults to the app's own.
    (data (i32.const 1024) "\\82\\a2\\62\\64\\6f\\65\\70\\72\\69\\6e\\74\\64\\74\\65\\78\\74\\6f\\67\\72\\65\\65\\74\\69\\6e\\67\\20\\73\\74\\6f\\72\\65\\64\\a4\\64\\61\\72\\67\\73\\a1\\66\\6c\\6f\\67\\5f\\69\\64\\19\\0a\\d9\\62\\64\\6f\\64\\77\\61\\6e\\74\\62\\6f\\70\\68\\6c\\6f\\67\\5f\\68\\65\\61\\64\\63\\72\\65\\66\\04")

    ;; Turn 3, the reply to ref 3, 191 bytes at 1536: a print and four
    ;; wants in the same array — refs and entry_meta of the newest entry the
    ;; listing log holds, the identity's own timeline, and its own profile.
    ;; Four replies follow, one per turn, in the order written.
    (data (i32.const 1536) "\\85\\a2\\62\\64\\6f\\65\\70\\72\\69\\6e\\74\\64\\74\\65\\78\\74\\6d\\68\\65\\6c\\6c\\6f\\20\\69\\73\\20\\62\\61\\63\\6b\\a4\\64\\61\\72\\67\\73\\a2\\66\\6c\\6f\\67\\5f\\69\\64\\19\\0a\\d9\\63\\73\\65\\71\\63\\6d\\61\\78\\62\\64\\6f\\64\\77\\61\\6e\\74\\62\\6f\\70\\64\\72\\65\\66\\73\\63\\72\\65\\66\\05\\a4\\64\\61\\72\\67\\73\\a2\\66\\6c\\6f\\67\\5f\\69\\64\\19\\0a\\d9\\63\\73\\65\\71\\63\\6d\\61\\78\\62\\64\\6f\\64\\77\\61\\6e\\74\\62\\6f\\70\\6a\\65\\6e\\74\\72\\79\\5f\\6d\\65\\74\\61\\63\\72\\65\\66\\06\\a4\\64\\61\\72\\67\\73\\a0\\62\\64\\6f\\64\\77\\61\\6e\\74\\62\\6f\\70\\68\\74\\69\\6d\\65\\6c\\69\\6e\\65\\63\\72\\65\\66\\07\\a4\\64\\61\\72\\67\\73\\a0\\62\\64\\6f\\64\\77\\61\\6e\\74\\62\\6f\\70\\67\\70\\72\\6f\\66\\69\\6c\\65\\63\\72\\65\\66\\08")

    ;; Turn 4, the reply to ref 4, 168 bytes at 2048: a render of a col
    ;; holding all four widgets (text, row, canvas) and a print. A view is
    ;; plain data; the pane decides how to draw it.
    (data (i32.const 2048) "\\82\\a2\\62\\64\\6f\\66\\72\\65\\6e\\64\\65\\72\\64\\76\\69\\65\\77\\a2\\64\\6b\\69\\64\\73\\83\\a2\\61\\73\\78\\21\\6c\\6f\\67\\20\\68\\65\\61\\64\\3a\\20\\74\\68\\65\\20\\6c\\69\\73\\74\\69\\6e\\67\\20\\6c\\6f\\67\\20\\61\\6e\\73\\77\\65\\72\\73\\61\\74\\64\\74\\65\\78\\74\\a2\\64\\6b\\69\\64\\73\\82\\a2\\61\\73\\69\\68\\65\\6c\\6c\\6f\\2d\\61\\70\\70\\61\\74\\64\\74\\65\\78\\74\\a2\\61\\73\\62\\76\\31\\61\\74\\64\\74\\65\\78\\74\\61\\74\\63\\72\\6f\\77\\a3\\61\\68\\18\\30\\61\\74\\66\\63\\61\\6e\\76\\61\\73\\61\\77\\18\\60\\61\\74\\63\\63\\6f\\6c\\a2\\62\\64\\6f\\65\\70\\72\\69\\6e\\74\\64\\74\\65\\78\\74\\6d\\68\\65\\61\\64\\20\\61\\6e\\73\\77\\65\\72\\65\\64")

    ;; The same turn when the host refused instead, 111 bytes at 2560: a
    ;; render carrying a plain map, which is not a widget tree, so the pane
    ;; dumps it as text rather than failing. A refusal is data too.
    (data (i32.const 2560) "\\82\\a2\\62\\64\\6f\\66\\72\\65\\6e\\64\\65\\72\\64\\76\\69\\65\\77\\a1\\64\\74\\65\\78\\74\\78\\3a\\6c\\6f\\67\\20\\68\\65\\61\\64\\20\\72\\65\\66\\75\\73\\65\\64\\3a\\20\\74\\68\\69\\73\\20\\6b\\65\\79\\20\\68\\61\\73\\20\\77\\72\\69\\74\\74\\65\\6e\\20\\6e\\6f\\74\\68\\69\\6e\\67\\20\\74\\6f\\20\\6c\\6f\\67\\20\\32\\37\\37\\37\\a2\\62\\64\\6f\\65\\70\\72\\69\\6e\\74\\64\\74\\65\\78\\74\\6c\\68\\65\\61\\64\\20\\72\\65\\66\\75\\73\\65\\64")

    ;; Turn 5, the reply to ref 5 (refs), 38 bytes at 2816. A reply is
    ;; delivered whether it carries the lists or a refusal, so the print
    ;; reports the round trip rather than guessing at the answer.
    (data (i32.const 2816) "\\81\\a2\\62\\64\\6f\\65\\70\\72\\69\\6e\\74\\64\\74\\65\\78\\74\\75\\72\\65\\66\\73\\3a\\20\\72\\65\\70\\6c\\79\\20\\64\\65\\6c\\69\\76\\65\\72\\65\\64")

    ;; Turn 6, the reply to ref 6 (entry_meta), 38 bytes at 3072: the
    ;; entry's tags, reactions and mentions arrive the same way.
    (data (i32.const 3072) "\\81\\a2\\62\\64\\6f\\65\\70\\72\\69\\6e\\74\\64\\74\\65\\78\\74\\75\\6d\\65\\74\\61\\3a\\20\\72\\65\\70\\6c\\79\\20\\64\\65\\6c\\69\\76\\65\\72\\65\\64")

    ;; Turn 7, the reply to ref 7 (timeline), 43 bytes at 3328: what
    ;; this identity wrote, as a page.
    (data (i32.const 3328) "\\81\\a2\\62\\64\\6f\\65\\70\\72\\69\\6e\\74\\64\\74\\65\\78\\74\\78\\19\\74\\69\\6d\\65\\6c\\69\\6e\\65\\3a\\20\\72\\65\\70\\6c\\79\\20\\64\\65\\6c\\69\\76\\65\\72\\65\\64")

    ;; Turn 8, the reply to ref 8 (profile), 170 bytes at 3584: the last
    ;; turn decides, the way turn 4 did — the render is what the profile read
    ;; left standing.
    (data (i32.const 3584) "\\82\\a2\\62\\64\\6f\\66\\72\\65\\6e\\64\\65\\72\\64\\76\\69\\65\\77\\a2\\64\\6b\\69\\64\\73\\82\\a2\\61\\73\\78\\29\\66\\6f\\75\\72\\20\\72\\65\\61\\64\\73\\3a\\20\\72\\65\\66\\73\\2c\\20\\6d\\65\\74\\61\\2c\\20\\74\\69\\6d\\65\\6c\\69\\6e\\65\\2c\\20\\70\\72\\6f\\66\\69\\6c\\65\\61\\74\\64\\74\\65\\78\\74\\a2\\64\\6b\\69\\64\\73\\82\\a2\\61\\73\\69\\68\\65\\6c\\6c\\6f\\2d\\61\\70\\70\\61\\74\\64\\74\\65\\78\\74\\a2\\61\\73\\62\\76\\31\\61\\74\\64\\74\\65\\78\\74\\61\\74\\63\\72\\6f\\77\\61\\74\\63\\63\\6f\\6c\\a2\\62\\64\\6f\\65\\70\\72\\69\\6e\\74\\64\\74\\65\\78\\74\\78\\18\\70\\72\\6f\\66\\69\\6c\\65\\3a\\20\\72\\65\\70\\6c\\79\\20\\64\\65\\6c\\69\\76\\65\\72\\65\\64")

    ;; The same turn when the host refused instead, 33 bytes at 3840: a
    ;; print only, so the render from turn 4 stays on the pane.
    (data (i32.const 3840) "\\81\\a2\\62\\64\\6f\\65\\70\\72\\69\\6e\\74\\64\\74\\65\\78\\74\\70\\70\\72\\6f\\66\\69\\6c\\65\\3a\\20\\72\\65\\66\\75\\73\\65\\64")

    ;; Any later turn, 1 byte at 8: the empty array. Saying nothing is legal,
    ;; and cheaper than guessing what to say.
    (data (i32.const 8) "\\80")

    ;; Does the host's message hold an `err` envelope? CBOR spells the three
    ;; letters "err" as the four bytes 63 65 72 72 — a text(3) header and the
    ;; letters — and nothing else in a reply spells that, so this branch needs
    ;; no decoder: scan for four bytes and count on the header. The scan stops
    ;; four bytes short of the end, so it never reads past the message.
    (func $is_err (param $p i32) (param $n i32) (result i32)
      (local $i i32)
      (local $q i32)
      (block $done
        (loop $scan
          (br_if $done (i32.gt_u (i32.add (local.get $i) (i32.const 4)) (local.get $n)))
          (local.set $q (i32.add (local.get $p) (local.get $i)))
          (if (i32.and
                (i32.and
                  (i32.eq (i32.load8_u (local.get $q)) (i32.const 0x63))
                  (i32.eq (i32.load8_u (i32.add (local.get $q) (i32.const 1))) (i32.const 0x65)))
                (i32.and
                  (i32.eq (i32.load8_u (i32.add (local.get $q) (i32.const 2))) (i32.const 0x72))
                  (i32.eq (i32.load8_u (i32.add (local.get $q) (i32.const 3))) (i32.const 0x72))))
            (then (return (i32.const 1))))
          (local.set $i (i32.add (local.get $i) (i32.const 1)))
          (br $scan)))
      (i32.const 0))

    (func (export "handle") (param $in i32) (param $in_len i32) (result i32)
      (local $turn i32)
      (local $answer i32)
      (local $len i32)
      (local.set $turn (global.get $state))
      (global.set $state (i32.add (local.get $turn) (i32.const 1)))
      (block $done
        (if (i32.eq (local.get $turn) (i32.const 0))
          (then
            (local.set $len (i32.const 151))
            (local.set $answer (i32.const 16))
            (br $done)))
        (if (i32.eq (local.get $turn) (i32.const 1))
          (then
            (local.set $len (i32.const 74))
            (local.set $answer (i32.const 512))
            (br $done)))
        (if (i32.eq (local.get $turn) (i32.const 2))
          (then
            (local.set $len (i32.const 74))
            (local.set $answer (i32.const 1024))
            (br $done)))
        (if (i32.eq (local.get $turn) (i32.const 3))
          (then
            (local.set $len (i32.const 191))
            (local.set $answer (i32.const 1536))
            (br $done)))
        ;; Ref 4 asked for a log head, and the answer is either the entries
        ;; or a refusal.
        (if (i32.eq (local.get $turn) (i32.const 4))
          (then
            (if (call $is_err (local.get $in) (local.get $in_len))
              (then
                (local.set $len (i32.const 111))
                (local.set $answer (i32.const 2560))
                (br $done))
              (else
                (local.set $len (i32.const 168))
                (local.set $answer (i32.const 2048))
                (br $done)))))
        (if (i32.eq (local.get $turn) (i32.const 5))
          (then
            (local.set $len (i32.const 38))
            (local.set $answer (i32.const 2816))
            (br $done)))
        (if (i32.eq (local.get $turn) (i32.const 6))
          (then
            (local.set $len (i32.const 38))
            (local.set $answer (i32.const 3072))
            (br $done)))
        (if (i32.eq (local.get $turn) (i32.const 7))
          (then
            (local.set $len (i32.const 43))
            (local.set $answer (i32.const 3328))
            (br $done)))
        ;; The last turn reads the host before speaking, the way turn 4 did:
        ;; ref 8 asked for a profile, and the answer is either what the key
        ;; said about itself or a refusal.
        (if (i32.eq (local.get $turn) (i32.const 8))
          (then
            (if (call $is_err (local.get $in) (local.get $in_len))
              (then
                (local.set $len (i32.const 33))
                (local.set $answer (i32.const 3840))
                (br $done))
              (else
                (local.set $len (i32.const 170))
                (local.set $answer (i32.const 3584))
                (br $done)))))
        (local.set $len (i32.const 1))
        (local.set $answer (i32.const 8)))
      ;; length of the answer at address 0, and where it starts
      (i32.store (i32.const 0) (local.get $len))
      (local.get $answer))
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
