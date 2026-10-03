defmodule CatenaryWeb.PlaygroundRunTest do
  use ExUnit.Case, async: true

  alias Catenary.Apps.DSL
  alias Catenary.Live.AppPlayground
  alias CatenaryWeb.Live

  # The nine-turn WAT draft the playground shipped with before the DSL
  # landed: a self-contained ABI tour whose replies are CBOR blobs written
  # out as data segments by hand. It stays here as the fixture behind the
  # blob guard below — the shape fixtures (planned, §9) will take.
  @wat_starter """
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

    ;; Turn 4, the reply to ref 4, 367 bytes at 2048: a render of a col
    ;; holding all four widgets (text, row, canvas), then five draw ops onto
    ;; the canvas it just declared — fill, stroke, line, path, text — and a
    ;; print. A view is plain data; the pane decides how to draw it, and a
    ;; draw clears and replays everything it carries in one effect.
    (data (i32.const 2048) "\\83\\a2\\62\\64\\6f\\66\\72\\65\\6e\\64\\65\\72\\64\\76\\69\\65\\77\\a2\\64\\6b\\69\\64\\73\\83\\a2\\61\\73\\78\\21\\6c\\6f\\67\\20\\68\\65\\61\\64\\3a\\20\\74\\68\\65\\20\\6c\\69\\73\\74\\69\\6e\\67\\20\\6c\\6f\\67\\20\\61\\6e\\73\\77\\65\\72\\73\\61\\74\\64\\74\\65\\78\\74\\a2\\64\\6b\\69\\64\\73\\82\\a2\\61\\73\\69\\68\\65\\6c\\6c\\6f\\2d\\61\\70\\70\\61\\74\\64\\74\\65\\78\\74\\a2\\61\\73\\62\\76\\31\\61\\74\\64\\74\\65\\78\\74\\61\\74\\63\\72\\6f\\77\\a3\\61\\68\\18\\30\\61\\74\\66\\63\\61\\6e\\76\\61\\73\\61\\77\\18\\60\\61\\74\\63\\63\\6f\\6c\\a2\\62\\64\\6f\\64\\64\\72\\61\\77\\63\\6f\\70\\73\\85\\a6\\61\\63\\67\\23\\32\\32\\63\\35\\35\\65\\61\\68\\18\\18\\62\\6f\\70\\69\\66\\69\\6c\\6c\\5f\\72\\65\\63\\74\\61\\77\\18\\28\\61\\78\\04\\61\\79\\04\\a6\\61\\68\\18\\18\\62\\6c\\77\\02\\62\\6f\\70\\6b\\73\\74\\72\\6f\\6b\\65\\5f\\72\\65\\63\\74\\61\\77\\18\\28\\61\\78\\04\\61\\79\\04\\a5\\62\\6f\\70\\64\\6c\\69\\6e\\65\\62\\78\\31\\04\\62\\78\\32\\18\\5c\\62\\79\\31\\18\\2c\\62\\79\\32\\18\\2c\\a5\\61\\63\\67\\23\\33\\62\\38\\32\\66\\36\\65\\63\\6c\\6f\\73\\65\\f5\\62\\6c\\77\\02\\62\\6f\\70\\6b\\73\\74\\72\\6f\\6b\\65\\5f\\70\\61\\74\\68\\63\\70\\74\\73\\83\\82\\18\\34\\08\\82\\18\\5c\\18\\1c\\82\\18\\34\\18\\2c\\a5\\62\\6f\\70\\64\\74\\65\\78\\74\\61\\73\\64\\64\\72\\61\\77\\64\\73\\69\\7a\\65\\0a\\61\\78\\06\\61\\79\\18\\28\\a2\\62\\64\\6f\\65\\70\\72\\69\\6e\\74\\64\\74\\65\\78\\74\\6d\\68\\65\\61\\64\\20\\61\\6e\\73\\77\\65\\72\\65\\64")

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

    ;; Turn 8, the reply to ref 8 (profile), 389 bytes at 3584: the last
    ;; turn decides, the way turn 4 did — the render (canvas and all) is what
    ;; the profile read left standing, and the same five ops redraw it with
    ;; their own label.
    (data (i32.const 3584) "\\83\\a2\\62\\64\\6f\\66\\72\\65\\6e\\64\\65\\72\\64\\76\\69\\65\\77\\a2\\64\\6b\\69\\64\\73\\83\\a2\\61\\73\\78\\29\\66\\6f\\75\\72\\20\\72\\65\\61\\64\\73\\3a\\20\\72\\65\\66\\73\\2c\\20\\6d\\65\\74\\61\\2c\\20\\74\\69\\6d\\65\\6c\\69\\6e\\65\\2c\\20\\70\\72\\6f\\66\\69\\6c\\65\\61\\74\\64\\74\\65\\78\\74\\a2\\64\\6b\\69\\64\\73\\82\\a2\\61\\73\\69\\68\\65\\6c\\6c\\6f\\2d\\61\\70\\70\\61\\74\\64\\74\\65\\78\\74\\a2\\61\\73\\62\\76\\31\\61\\74\\64\\74\\65\\78\\74\\61\\74\\63\\72\\6f\\77\\a3\\61\\68\\18\\30\\61\\74\\66\\63\\61\\6e\\76\\61\\73\\61\\77\\18\\60\\61\\74\\63\\63\\6f\\6c\\a2\\62\\64\\6f\\64\\64\\72\\61\\77\\63\\6f\\70\\73\\85\\a6\\61\\63\\67\\23\\32\\32\\63\\35\\35\\65\\61\\68\\18\\18\\62\\6f\\70\\69\\66\\69\\6c\\6c\\5f\\72\\65\\63\\74\\61\\77\\18\\28\\61\\78\\04\\61\\79\\04\\a6\\61\\68\\18\\18\\62\\6c\\77\\02\\62\\6f\\70\\6b\\73\\74\\72\\6f\\6b\\65\\5f\\72\\65\\63\\74\\61\\77\\18\\28\\61\\78\\04\\61\\79\\04\\a5\\62\\6f\\70\\64\\6c\\69\\6e\\65\\62\\78\\31\\04\\62\\78\\32\\18\\5c\\62\\79\\31\\18\\2c\\62\\79\\32\\18\\2c\\a5\\61\\63\\67\\23\\33\\62\\38\\32\\66\\36\\65\\63\\6c\\6f\\73\\65\\f5\\62\\6c\\77\\02\\62\\6f\\70\\6b\\73\\74\\72\\6f\\6b\\65\\5f\\70\\61\\74\\68\\63\\70\\74\\73\\83\\82\\18\\34\\08\\82\\18\\5c\\18\\1c\\82\\18\\34\\18\\2c\\a5\\62\\6f\\70\\64\\74\\65\\78\\74\\61\\73\\66\\74\\69\\65\\72\\20\\31\\64\\73\\69\\7a\\65\\0a\\61\\78\\06\\61\\79\\18\\28\\a2\\62\\64\\6f\\65\\70\\72\\69\\6e\\74\\64\\74\\65\\78\\74\\78\\18\\70\\72\\6f\\66\\69\\6c\\65\\3a\\20\\72\\65\\70\\6c\\79\\20\\64\\65\\6c\\69\\76\\65\\72\\65\\64")

    ;; The same turn when the host refused instead, 33 bytes at 640, out
    ;; of the turn order on purpose: a print only, so the render from turn 4
    ;; — canvas and all — stays on the pane.
    (data (i32.const 640) "\\81\\a2\\62\\64\\6f\\65\\70\\72\\69\\6e\\74\\64\\74\\65\\78\\74\\70\\70\\72\\6f\\66\\69\\6c\\65\\3a\\20\\72\\65\\66\\75\\73\\65\\64")

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
                (local.set $len (i32.const 367))
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
                (local.set $answer (i32.const 640))
                (br $done))
              (else
                (local.set $len (i32.const 389))
                (local.set $answer (i32.const 3584))
                (br $done)))))
        (local.set $len (i32.const 1))
        (local.set $answer (i32.const 8)))
      ;; length of the answer at address 0, and where it starts
      (i32.store (i32.const 0) (local.get $len))
      (local.get $answer))
  """

  # A bare socket has no `live_temp`, which is where `push_event/3` writes;
  # the run clause pushes, so the socket under test carries an empty one.
  defp socket(fields) do
    assigns = Map.merge(%{trace: [], trace_at: 0, __changed__: %{}}, Map.new(fields))

    %Phoenix.LiveView.Socket{
      private: %{live_temp: %{}},
      assigns: assigns
    }
  end

  defp pushed(socket), do: socket.private.live_temp[:push_events]

  test "a trace is appended in order and the cursor follows it to the tail" do
    entries = for i <- 1..3, do: %{"kind" => "print", "detail" => "line #{i}"}

    {:noreply, socket} = Live.handle_event("app-trace", %{"entries" => entries}, socket([]))

    assert Enum.map(socket.assigns.trace, & &1["detail"]) == ["line 1", "line 2", "line 3"]
    assert socket.assigns.trace_at == 2
  end

  test "a trace past the cap keeps only the newest entries" do
    entries = for i <- 1..250, do: %{"kind" => "print", "detail" => "line #{i}"}

    {:noreply, socket} = Live.handle_event("app-trace", %{"entries" => entries}, socket([]))

    assert length(socket.assigns.trace) == 200
    assert hd(socket.assigns.trace)["detail"] == "line 51"
    assert List.last(socket.assigns.trace)["detail"] == "line 250"
    assert socket.assigns.trace_at == 199
  end

  test "entries that are not a kind and detail pair are dropped" do
    entries = [
      "nope",
      %{"kind" => "stop"},
      %{"kind" => "print", "detail" => 7},
      %{"kind" => "stop", "detail" => "stopped"}
    ]

    {:noreply, socket} = Live.handle_event("app-trace", %{"entries" => entries}, socket([]))

    assert [%{"kind" => "stop", "detail" => "stopped"}] = socket.assigns.trace
  end

  test "a drop-in run starts the trace over" do
    {:noreply, socket} =
      Live.handle_event(
        "app-trace",
        %{"entries" => [%{"kind" => "print", "detail" => "from the last run"}]},
        socket([])
      )

    assert [_] = socket.assigns.trace

    {:noreply, socket} = Live.handle_event("app-run-start", %{}, socket)

    assert socket.assigns.trace == []
    assert socket.assigns.trace_at == 0
  end

  test "stepping clamps at both ends" do
    entries = for i <- 1..3, do: %{"kind" => "print", "detail" => "#{i}"}
    {:noreply, socket} = Live.handle_event("app-trace", %{"entries" => entries}, socket([]))

    {:noreply, socket} = Live.handle_event("trace-step", %{"value" => "next"}, socket)
    assert socket.assigns.trace_at == 2

    socket =
      Enum.reduce(1..5, socket, fn _, socket ->
        {:noreply, socket} = Live.handle_event("trace-step", %{"value" => "prev"}, socket)
        socket
      end)

    assert socket.assigns.trace_at == 0
  end

  # The starter is the DSL tier's front door. It has to compile through the
  # DSL compiler — not parse as WAT by accident — and the compiled module
  # has to survive watusi, which is what the run below pushes.
  test "the starter is DSL source that compiles through the DSL path" do
    source = AppPlayground.starter_source()

    refute source =~ "(module"
    assert source =~ "on init:"

    assert {:ok, wat} = DSL.compile(source)
    assert is_binary(Watusi.to_wasm(wat))
  end

  test "the starter buffer compiles to a module" do
    {:noreply, socket} =
      Live.handle_info(:playground_run, socket(source: AppPlayground.starter_source()))

    assert socket.assigns.trace == []
    assert [event, %{"wasm" => wasm}] = List.first(pushed(socket))
    assert event == "app-run"
    module = Base.decode64!(wasm)
    assert binary_part(module, 0, 4) == <<0, 97, 115, 109>>
  end

  # The gutter marks want character offsets, not line and column: the
  # compiler's position is converted on the way out so it lands on the
  # character the author sees it on.
  test "editor diagnostics arrive as document coordinates" do
    source = ~S|on init:
  print(x)
|

    {:noreply, socket} =
      Live.handle_event("playground-source", %{"value" => source}, socket([]))

    assert [event, %{"diagnostics" => diagnostics}] = List.first(pushed(socket))
    assert event == "playground-diagnostics"
    # "on init:" is 8 characters plus its newline, and x is column 9 of the
    # line after it: offset 17, a one-character mark under the x.
    assert diagnostics == [%{"from" => 17, "to" => 18, "message" => "x is not defined"}]
  end

  # A JavaScript string indexes UTF-16 code units, so every astral character
  # before the error shifts its mark one unit right of a codepoint count.
  test "an emoji before the error counts twice in document coordinates" do
    source = ~S|on init:
  let a = "🙂"
  print(x)
|

    {:noreply, socket} =
      Live.handle_event("playground-source", %{"value" => source}, socket([]))

    assert ["playground-diagnostics", %{"diagnostics" => [diagnostic]}] =
             List.first(pushed(socket))

    # Line 2 holds 13 codepoints but 14 units, so line 3 starts at 24 and
    # column 9 lands at 32 — one past what counting codepoints would give.
    assert diagnostic["from"] == 32
    assert diagnostic["to"] == 33
    assert diagnostic["message"] == "x is not defined"
  end

  test "a buffer that compiles, or that is WAT, carries no marks" do
    source = AppPlayground.starter_source()

    {:noreply, socket} = Live.handle_event("playground-source", %{"value" => source}, socket([]))
    assert ["playground-diagnostics", %{"diagnostics" => []}] = List.first(pushed(socket))

    {:noreply, socket} =
      Live.handle_event("playground-source", %{"value" => @wat_starter}, socket([]))

    assert ["playground-diagnostics", %{"diagnostics" => []}] = List.first(pushed(socket))
  end

  # The effect blobs are written out as escapes by hand, so a wrong one
  # still compiles: the module answers with bytes the host cannot read, and
  # the pane would be the first thing to say so. Decoding them here is the
  # check that would otherwise be left to a run.
  test "every effect blob in the WAT fixture is one clean CBOR value" do
    source = @wat_starter

    blobs =
      for [_, address, payload] <-
            Regex.scan(~r/\(data \(i32\.const (\d+)\) "([^"]*)"\)/, source) do
        bytes =
          Regex.replace(~r/\\([0-9a-fA-F]{2})/, payload, fn _, hex ->
            <<String.to_integer(hex, 16)>>
          end)

        refute String.contains?(String.replace(payload, ~r/\\[0-9a-fA-F]{2}/, ""), "\\"),
               "a stray escape at address #{address}"

        decoded =
          try do
            CBOR.decode(bytes)
          rescue
            error -> {:undecodable, Exception.message(error)}
          end

        assert match?({:ok, _value, ""}, decoded),
               "address #{address} is not one CBOR value with nothing after it: #{inspect(decoded)}"

        {String.to_integer(address), byte_size(bytes)}
      end

    assert length(blobs) == 12
    assert Enum.uniq(Enum.map(blobs, &elem(&1, 0))) |> length() == 12
    # nothing may reach 0x1000, where the host writes the message it delivers
    assert Enum.all?(blobs, fn {address, size} -> address + size <= 0x1000 end)

    declared =
      for [_, digits] <- Regex.scan(~r/local\.set \$len \(i32\.const (\d+)\)/, source),
          do: String.to_integer(digits)

    assert Enum.sort(declared) == Enum.map(blobs, &elem(&1, 1)) |> Enum.sort()
  end

  test "a buffer that does not parse is a compile entry and a status payload" do
    {:noreply, socket} = Live.handle_info(:playground_run, socket(source: "not wat at all"))

    assert [%{"kind" => "compile", "detail" => detail}] = socket.assigns.trace
    assert is_binary(detail)
    assert [event, %{"error" => message}] = List.first(pushed(socket))
    assert event == "app-run"
    assert is_binary(message)
  end
end
