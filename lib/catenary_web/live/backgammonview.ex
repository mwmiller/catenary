defmodule Catenary.Live.BackgammonView do
  @moduledoc """
  LiveComponent rendering a backgammon game: participants, opening state, turn
  state, the board, the interactive move UI (roll + pick a legal play +
  publish), and a replay scrubber that steps through every folded turn.

  A game row comes from the `:challenges` index (keyed by hex `game_id`). The
  index worker folds the play log (see `Catenary.Games.Backgammon.Fold`), which
  resolves the opening rolls, the starter, and the board/turn state, landing
  them on the row. This component draws it and drives the next entry.

  * Before a starter is decided, the game is **opening**: a `roll` entry
    publishes one player's half of an opening round (alternating challenger,
    accepter). Once the starter is known, play proceeds in normal turns.
  * Turns count **up from 1** (starter plays the odd ones); reveals count
    **down from the chain length**, and the fold's `remaining` map tells each
    player how many of their own reveals are left.

  Movable and roll actions are published to the parent LiveView
  (`publish-roll`, `publish-turn`); the reveal-derived roll, the board
  move entry (natural tap-to-move, with a full-play list fallback), and
  the replay scrubber are local component state. On the viewer's turn the
  board renders the prepared moves as if already made — a partial play or a
  picked list play previews with the checkers moved — with legal destination
  points' triangles lightly glowing.

  Scrubbing to a turn renders the diff on the checkers themselves: stacks
  that gained a checker light up with a single uniform green ring and glow on
  every pip of the stack, and stacks that lost one show an empty dashed ghost
  pip where the checker no longer stands (a hit likewise shows the knocked
  checker arriving on the far bar) — so a turn reads as pieces arriving and
  departing across the board.
  """
  use Phoenix.LiveComponent

  alias Catenary.{
    Games.Backgammon.Chain,
    Games.Backgammon.Engine,
    Games.Backgammon.Game,
    Games.Backgammon.Notation,
    Display,
    LogWriter
  }

  @chain_length Chain.spec()["length"]

  @impl true
  def update(%{game_id: game_id, identity: identity} = assigns, socket) do
    case game_row(game_id) do
      nil ->
        # A full reindex ("reindex and replace") momentarily empties the game
        # table, so acting on the :index_change nudge can race that window.
        # Hold the current row instead of crashing; a brand-new mount with no
        # row yet draws the "not indexed yet" face until it returns.
        {:ok, assign(socket, assigns)}

      game ->
        update_assigns(assigns, socket, game, identity)
    end
  end

  defp update_assigns(assigns, socket, game, identity) do
    assigns =
      Map.merge(assigns, %{
        game: game,
        history: Map.get(game, :history, []),
        live_position: live_position(game)
      })

    assigns = Map.merge(assigns, involvement(assigns, game, identity))

    # Pre-warm our scrypt chain for this game in the background (once per
    # mount) so the local Roll lands on the memoised chain instead of a ~10s
    # build on the click path.
    assigns =
      if Map.get(assigns, :involved, false) and not Map.get(assigns, :chain_warm, false) do
        warm_chain(Map.put(assigns, :chain_warm, true), game)
      else
        assigns
      end

    # A fold advancing (our own publish or the opponent's) resets the local
    # play/replay state so the board always points at the live position.
    assigns =
      if Map.get(assigns, :seen_turns, nil) == Map.get(game, :turn_count, 0) do
        assigns
      else
        # The first turn after the opening uses the opener dice directly —
        # no separate roll step.  Every subsequent turn requires a fresh roll.
        first_turn? = game.turn_count == 0 and game.phase == :playing
        opener = Map.get(game, :opener)

        {auto_rolled, opener_roll} =
          if first_turn? and is_map(opener) and is_list(opener.dice) do
            [d1, d2] = opener.dice
            {true, {d1, d2}}
          else
            {false, nil}
          end

        Map.merge(assigns, %{
          seen_turns: Map.get(game, :turn_count, 0),
          has_rolled: auto_rolled,
          roll: opener_roll,
          pending: nil,
          build: nil,
          show_plays: false,
          note: "",
          roll_error: false,
          replay: %{step: Map.get(game, :turn_count, 0)}
        })
      end

    {:ok, assign(socket, assigns)}
  end

  defp live_position(game), do: Map.get(game, :position, Engine.initial())

  defp involvement(assigns, %{challenger: challenger, accepter: accepter} = game, identity) do
    involved = is_binary(accepter) and identity in [challenger, accepter]
    mover = Map.get(game, :mover)
    opening = Map.get(game, :phase, :opening) == :opening
    # Before the fold has re-indexed after a publish, mover is nil.
    # Hide all interactive controls until the fold resolves to avoid
    # duplicate roll/turn entries from stale state.
    my_roll = involved and opening and is_binary(mover) and mover == identity

    Map.merge(assigns, %{
      involved: involved,
      my_turn: involved and not opening and mover == identity,
      my_roll: my_roll,
      opening: opening,
      mover: mover
    })
  end

  defp game_row(game_id) do
    case :ets.lookup(:challenges, {:game, game_id}) do
      [{_, game}] -> fold_defaults(game)
      [] -> nil
    end
  end

  # The fold may not have run yet when the view mounts fast (e.g. the play
  # button navigates immediately). Present the same shape either way so the
  # render never crashes on a missing fold field — the index worker fills the
  # real values in on the next pass and BackgammonView re-reads them.
  defp fold_defaults(game) do
    Map.merge(
      %{
        fold_error: :none,
        position: Engine.initial(),
        turn_count: Map.get(game, :turn_count, 0),
        mover: nil,
        winner: nil,
        phase: :opening,
        opener: nil,
        history: [],
        remaining: %{},
        chains: %{}
      },
      game
    )
  end

  @impl true
  def render(%{game: nil} = assigns) do
    ~H"""
    <div class="content-wrap">
      <div class="rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-4">
        <h1 class="text-lg font-semibold text-slate-800 dark:text-slate-100">Game not indexed yet</h1>
        <p class="text-slate-500 dark:text-slate-400 text-sm mt-1">
          The challenges index hasn't caught up to this game. Give it a moment and reload.
        </p>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="content-wrap">
      <div class="rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-4">
        <div class="flex items-center justify-between gap-2">
          <div class="flex flex-col gap-1 min-w-0">
            <div class="flex items-center gap-2">
              <% show_winner? =
                case Map.get(@game, :winner) do
                  nil -> false
                  _ -> not active_replay?(@replay) or live_frame?(assigns)
                end %>
              <% label =
                cond do
                  show_winner? ->
                    "won (#{Map.get(@game, :winner).stake}x)"

                  @opening ->
                    "opening"

                  active_replay?(@replay) ->
                    "Turn #{replay_step(@replay)}"

                  true ->
                    "Turn #{@game.turn_count + 1}"
                end %>
              <% badge_cls =
                cond do
                  show_winner? -> "bg-emerald-600 text-white"
                  @opening -> "bg-amber-500 text-white"
                  true -> "bg-sky-500 text-white"
                end %>
              <%= if show_winner? do %>
                <span class={"px-1.5 py-0.5 rounded text-[10px] font-bold uppercase inline-flex items-center gap-1 " <> badge_cls}>
                  {label}
                  {Display.scaled_avatar(Map.get(@game, :winner).player, 1) |> Phoenix.HTML.raw()}
                  {Display.linked_author(Map.get(@game, :winner).player, @aliases)}
                </span>
              <% else %>
                <span class={"px-1.5 py-0.5 rounded text-[10px] font-bold uppercase " <> badge_cls}>{label}</span>
              <% end %>
              <span class="text-xs text-slate-400 dark:text-slate-600">
                {Display.pretty_game_id(@game_id)}
              </span>
              <%= if @involved and not @opening and Map.get(@game, :winner) == nil do %>
                <button
                  type="button"
                  phx-click="pick-play"
                  phx-target={@myself}
                  phx-value-index="resign"
                  class={"px-1.5 py-0.5 rounded text-[10px] font-bold uppercase " <> resign_badge_cls(assigns)}
                  title="Resign this game"
                  aria-label="Resign this game"
                >☠</button>
              <% end %>
            </div>
          </div>
          <div class="text-sm shrink-0">
            <% c_active =
              case Map.get(@game, :winner) do
                %{player: player} -> player == @game.challenger
                _ -> @mover == @game.challenger
              end %>
            <span class={"inline-flex items-center gap-1 " <> if c_active, do: "font-semibold text-amber-600 dark:text-amber-400", else: ""}>
              {Display.scaled_avatar(@game.challenger, 1) |> Phoenix.HTML.raw()}
              {Display.linked_author(@game.challenger, @aliases)}
            </span>
            <span class="mx-1 text-slate-400 dark:text-slate-600">vs</span>
            <span class={"inline-flex items-center gap-1 " <> if not c_active, do: "font-semibold text-amber-600 dark:text-amber-400", else: ""}>
              {Display.scaled_avatar(@game.accepter, 1) |> Phoenix.HTML.raw()}
              {Display.linked_author(@game.accepter, @aliases)}
            </span>
          </div>
          <%= if Map.get(@game, :fold_error) != :none do %>
            <span
              class="text-[10px] uppercase tracking-wide text-amber-600 dark:text-amber-400 mt-1"
              title={"#{Map.get(@game, :fold_error) || "fold unfinished"}"}
            >
              fold {fold_error_label(Map.get(@game, :fold_error))}
            </span>
          <% end %>
        </div>

        <% disp = board_display(assigns) %>
        <% {disp_pos, _disp_actor} = disp %>
        <div class="mt-4">{board(disp, assigns, @myself.cid)}</div>

        <% {pips_c, _bar_c, _off_c} =
          rail_stats(disp_pos, participant_role(@game, @identity, "challenger")) %>
        <% {pips_a, _bar_a, _off_a} =
          rail_stats(disp_pos, participant_role(@game, @identity, "accepter")) %>

        <div class="mt-3 flex items-baseline justify-between gap-3 font-mono text-[11px] text-slate-500 dark:text-slate-400">
          <div class="flex items-baseline gap-1.5 min-w-0">
            <span class="max-w-[7rem] truncate">{compact_name(@game.challenger, @aliases)}</span>
            {opening_pip(@game, "challenger")}
            <span class="whitespace-nowrap">pips {pips_c}</span>
          </div>
          <div class="flex items-baseline gap-1.5 min-w-0">
            <span class="whitespace-nowrap">pips {pips_a}</span>
            {opening_pip(@game, "accepter")}
            <span class="max-w-[7rem] truncate">{compact_name(@game.accepter, @aliases)}</span>
          </div>
        </div>

        <div class="mt-3 flex items-center justify-between gap-3 w-full">
          <div class="min-w-0 truncate">{turn_note(assigns)}</div>
          <%= unless @opening do %>
            <div class="flex items-center gap-1.5 shrink-0">
              {dice_pips(display_roll(assigns))}
              <%= if @my_turn and not @has_rolled and Map.get(@game, :winner) == nil do %>
                <button
                  phx-click="roll-dice"
                  phx-target={@myself}
                  title="Roll dice"
                  aria-label="Roll dice"
                  class="rounded-md border border-slate-300 dark:border-slate-700 text-slate-600 dark:text-slate-400 hover:border-slate-500 dark:hover:border-slate-500 hover:text-slate-800 dark:hover:text-slate-200 text-sm px-2 py-0.5 transition-colors"
                >↻</button>
              <% end %>
            </div>
          <% end %>
        </div>

        <%= if @involved and Map.get(@game, :winner) == nil do %>
          <div class="mt-3 border-t border-slate-200 dark:border-slate-700 pt-3">
            <%= cond do %>
              <% @opening && @my_roll -> %>
                <form phx-submit="publish-roll" phx-target={@myself} class="flex items-center gap-2">
                  <input type="hidden" name="game_id" value={@game.game_id} />
                  <input type="hidden" name="round" value={get_in(@game, [:opener, :rounds]) || 0} />
                  <button
                    type="submit"
                    phx-disable-with="𝄇"
                    title="Roll your die"
                    aria-label="Roll your die"
                    class="rounded-md bg-amber-500 hover:bg-amber-400 active:bg-amber-600 dark:bg-amber-400 dark:hover:bg-amber-300 dark:active:bg-amber-500 text-white dark:text-slate-900 text-sm font-semibold px-3 py-1.5 shadow-sm transition-colors"
                  >↻</button>
                </form>
              <% @my_turn && !@has_rolled -> %>
                <%= if @pending == :resign do %>
                  <div class="flex items-center gap-2">
                    <span class="font-mono text-red-700 dark:text-red-300 text-xs">☠ resign selected</span>
                    <button
                      type="button"
                      phx-click="build-clear"
                      phx-target={@myself}
                      title="Clear selection"
                      aria-label="Clear selection"
                      class="px-2 py-0.5 rounded border border-slate-300 dark:border-slate-600 hover:border-sky-400"
                    >✕</button>
                    <form phx-change="note-change" phx-target={@myself} class="flex-1">
                      <input
                        type="text"
                        name="note"
                        value={@note}
                        placeholder="Optional turn note"
                        maxlength="140"
                        class="w-full rounded border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800 px-2 py-1 text-sm min-w-0"
                      />
                    </form>
                    <button
                      type="button"
                      phx-click="publish-resign"
                      phx-disable-with="𝄇"
                      phx-value-game_id={@game.game_id}
                      phx-value-turn={@game.turn_count + 1}
                      phx-value-note={@note}
                      title="Resign game"
                      aria-label="Resign game"
                      class="rounded-md bg-amber-500 hover:bg-amber-400 active:bg-amber-600 dark:bg-amber-400 dark:hover:bg-amber-300 dark:active:bg-amber-500 text-white dark:text-slate-900 text-sm font-semibold px-3 py-1.5 shadow-sm transition-colors"
                    >➲</button>
                  </div>
                <% else %>
                  <form phx-change="note-change" phx-target={@myself} class="flex items-center gap-2">
                    <input
                      type="text"
                      name="note"
                      value={@note}
                      placeholder="Optional turn note"
                      maxlength="140"
                      class="flex-1 rounded border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800 px-2 py-1 text-sm min-w-0"
                    />
                  </form>
                <% end %>
              <% @my_turn -> %>
                <div class="flex flex-col gap-2">
                  <%= if @build != nil and Map.get(@build, :from) != nil do %>
                    <div class="flex flex-wrap items-center gap-1.5 text-xs">
                      <span class="text-slate-500 dark:text-slate-400">
                        from {Notation.point_name(Map.get(@build, :from))}
                      </span>
                      <%= for chip <- reach_chips(assigns) do %>
                        <button
                          type="button"
                          phx-click="build-dest"
                          phx-target={@myself}
                          phx-value-dest={chip.dest}
                          class="px-2.5 py-1 rounded border border-sky-400 text-sky-700 dark:text-sky-300 font-mono hover:bg-sky-50 dark:hover:bg-sky-950"
                        >
                          {chip.label}
                        </button>
                      <% end %>
                      <button
                        type="button"
                        phx-click="build-undo"
                        phx-target={@myself}
                        title="Undo last move"
                        aria-label="Undo last move"
                        class="px-2 py-0.5 rounded border border-slate-300 dark:border-slate-600 hover:border-sky-400"
                      >↩</button>
                      <button
                        type="button"
                        phx-click="build-clear"
                        phx-target={@myself}
                        title="Clear all moves"
                        aria-label="Clear all moves"
                        class="px-2 py-0.5 rounded border border-slate-300 dark:border-slate-600 hover:border-sky-400"
                      >✕</button>
                    </div>
                    <%= if build_notation(assigns) != "" and not build_complete?(assigns) do %>
                      <div class="flex items-center gap-2 text-xs font-mono text-sky-700 dark:text-sky-300">
                        <span>→ so far: {build_notation(assigns)}</span>
                      </div>
                    <% end %>
                  <% end %>

                  <%= if @pending != nil do %>
                    <div class="flex flex-wrap items-center gap-1.5 text-xs">
                      <span class={
                        if @pending == :resign,
                          do: "font-mono text-red-700 dark:text-red-300",
                          else: "font-mono text-sky-700 dark:text-sky-300"
                      }>
                        <%= cond do %>
                          <% @pending == :pass -> %>
                            pass selected
                          <% @pending == :resign -> %>
                            ☠ resign selected
                          <% true -> %>
                            {Notation.turn(@pending)} selected
                        <% end %>
                      </span>
                      <button
                        type="button"
                        phx-click="build-clear"
                        phx-target={@myself}
                        title="Clear selection"
                        aria-label="Clear selection"
                        class="px-2 py-0.5 rounded border border-slate-300 dark:border-slate-600 hover:border-sky-400"
                      >✕</button>
                    </div>
                  <% end %>

                  <div class="flex items-center gap-2 mt-2">
                    <button
                      type="button"
                      phx-click="toggle-plays"
                      phx-target={@myself}
                      class="text-[11px] text-slate-500 dark:text-slate-400 hover:text-slate-700 dark:hover:text-slate-200 transition-colors"
                    >
                      {if @show_plays,
                        do: "▾ hide plays",
                        else: "▸ #{length(Enum.reject(legal_plays_for(assigns), &(&1 == [])))} plays"}
                    </button>
                  </div>

                  <%= if @show_plays do %>
                    <div class="flex flex-wrap gap-1.5">
                      <%= for {play, i} <- Enum.with_index(legal_plays_for(assigns)), play != [] do %>
                        <button
                          phx-click="pick-play"
                          phx-target={@myself}
                          phx-value-index={i}
                          class={"px-2.5 py-1 rounded border font-mono text-xs " <> play_cls(assigns, play)}
                        >
                          {Notation.turn(play)}
                        </button>
                      <% end %>
                      <%= if stand_only?(assigns) or build_stand?(assigns) do %>
                        <button
                          phx-click="pick-play"
                          phx-target={@myself}
                          phx-value-index="pass"
                          class={"px-2.5 py-1 rounded border font-mono text-xs " <> play_cls(assigns, :pass)}
                        >
                          no moves — pass
                        </button>
                      <% end %>
                    </div>
                  <% end %>

                  <%= if elected = elected_play(assigns) do %>
                    <div class="rounded border border-sky-300 dark:border-sky-700 bg-sky-50 dark:bg-sky-950/40 px-2 py-1.5 font-mono text-xs text-sky-800 dark:text-sky-200">
                      <div class="flex items-center gap-1.5">
                        <span class="uppercase tracking-wide text-[10px] text-slate-500 dark:text-slate-400">Publish</span>
                        <span class="font-semibold">→ complete:</span>
                        <span>{Notation.turn(elected)}</span>
                      </div>
                      <div class="flex items-baseline gap-1.5 mt-0.5 text-[11px] text-slate-500 dark:text-slate-400">
                        <span>you:</span>
                        {effect_line(assigns, elected, :actor)}
                        <span class="mx-1">|</span>
                        <span>opponent:</span>
                        {effect_line(assigns, elected, :opponent)}
                      </div>
                    </div>
                  <% end %>

                  <form phx-change="note-change" phx-target={@myself} class="flex items-center gap-2">
                    <input
                      type="text"
                      name="note"
                      value={@note}
                      placeholder="Optional turn note"
                      maxlength="140"
                      class="flex-1 rounded border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800 px-2 py-1 text-sm min-w-0"
                    />
                    <%= if @pending == :resign do %>
                      <button
                        type="button"
                        phx-click="publish-resign"
                        phx-disable-with="𝄇"
                        phx-value-game_id={@game.game_id}
                        phx-value-turn={@game.turn_count + 1}
                        phx-value-note={@note}
                        disabled={not ready_to_publish?(assigns)}
                        title="Resign game"
                        aria-label="Resign game"
                        class="rounded-md bg-red-600 hover:bg-red-500 active:bg-red-700 dark:bg-red-500 dark:hover:bg-red-400 dark:active:bg-red-600 text-white dark:text-slate-900 text-sm font-semibold px-3 py-1.5 shadow-sm transition-colors disabled:opacity-40 disabled:bg-slate-400"
                      >☠</button>
                    <% else %>
                      <button
                        type="button"
                        phx-click="publish-turn"
                        phx-disable-with="𝄇"
                        phx-value-game_id={@game.game_id}
                        phx-value-turn={@game.turn_count + 1}
                        phx-value-roll={roll_string(@roll)}
                        phx-value-moves={moves_for(assigns)}
                        phx-value-note={@note}
                        disabled={not ready_to_publish?(assigns)}
                        title="Publish turn"
                        aria-label="Publish turn"
                        class="rounded-md bg-amber-500 hover:bg-amber-400 active:bg-amber-600 dark:bg-amber-400 dark:hover:bg-amber-300 dark:active:bg-amber-500 text-white dark:text-slate-900 text-sm font-semibold px-3 py-1.5 shadow-sm transition-colors disabled:opacity-40 disabled:bg-slate-400"
                      >➲</button>
                    <% end %>
                  </form>
                </div>
              <% true -> %>
            <% end %>
          </div>
        <% end %>

        <div class="mt-3 border-t border-slate-200 dark:border-slate-700 pt-3">
          <div class="flex items-center gap-2 text-xs text-slate-500 dark:text-slate-400">
            <span class="uppercase tracking-wide text-[10px]">Replay</span>
            <button
              phx-click="replay-start"
              phx-target={@myself}
              disabled={replay_step(@replay) == 0}
              class="px-2 py-0.5 rounded border border-slate-300 dark:border-slate-600 hover:border-sky-400 disabled:opacity-40"
            >«</button>
            <button
              phx-click="replay-prev"
              phx-target={@myself}
              disabled={replay_step(@replay) == 0}
              class="px-2 py-0.5 rounded border border-slate-300 dark:border-slate-600 hover:border-sky-400 disabled:opacity-40"
            >‹</button>
            <span class="font-mono">{replay_step(@replay)}/{turns(assigns)}</span>
            <button
              phx-click="replay-next"
              phx-target={@myself}
              disabled={replay_step(@replay) >= turns(assigns)}
              class="px-2 py-0.5 rounded border border-slate-300 dark:border-slate-600 hover:border-sky-400 disabled:opacity-40"
            >›</button>
            <button
              phx-click="replay-end"
              phx-target={@myself}
              disabled={replay_step(@replay) >= turns(assigns)}
              class="px-2 py-0.5 rounded border border-slate-300 dark:border-slate-600 hover:border-sky-400 disabled:opacity-40"
            >»</button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp fold_error_label(:none), do: "unverified"

  @fold_error_labels [
    {["starter was decided"], "turn arrived before the opening resolved"},
    {["opening round mismatch"], "opening rolls came back out of order"},
    {["reveal counter"], "reveal accounting didn't match"},
    {["chain violation"], "a reveal didn't match its commitment"},
    {["bad reveal hex"], "a reveal couldn't be read"},
    {["entropy exhausted"], "a player ran out of reveals"},
    {["sequence gap"], "a turn is missing"},
    {["illegal or non-maximal", "bad moves"], "a move didn't check out"},
    {["unreadable game log"], "game log unavailable"}
  ]

  defp fold_error_label(error) when is_binary(error) do
    cond do
      String.contains?(error, "opening roll") and String.contains?(error, "authored") ->
        "opening roll from the wrong player"

      String.contains?(error, "authored") ->
        "turn played by the wrong player"

      true ->
        lookup_fold_error(error)
    end
  end

  defp fold_error_label(_), do: "unverified"

  defp lookup_fold_error(error) do
    Enum.find_value(@fold_error_labels, "fold couldn't be verified", fn {keys, label} ->
      has_key = Enum.any?(keys, &String.contains?(error, &1))
      if has_key, do: label
    end)
  end

  # ---- local event handlers (roll reveal, pick, replay, note) ----

  @impl true
  def handle_event("roll-dice", _, socket) do
    case my_reveals(socket.assigns) do
      {r_cur, r_next, d1, d2} ->
        {:noreply,
         socket
         |> assign(
           has_rolled: true,
           roll: {d1, d2},
           reveals: %{r_cur: r_cur, r_next: r_next},
           roll_error: false,
           show_plays: false
         )}

      :error ->
        {:noreply, assign(socket, roll_error: true)}
    end
  end

  def handle_event("pick-play", %{"index" => index}, socket) do
    assigns = socket.assigns

    pending =
      cond do
        index == "pass" ->
          :pass

        index == "resign" ->
          :resign

        true ->
          case Enum.at(legal_plays_for(assigns), String.to_integer(index)) do
            nil -> nil
            play -> play
          end
      end

    {:noreply, assign(socket, pending: pending, build: nil)}
  end

  # Tap-to-move: `point` is the tapped point number, or `"bar"`. A tap with
  # no source picked (and on a usable source) selects it; a tap on the picked
  # source deselects; any other tap is a destination (or a no-op if not one
  # of the glowing legal landings for the current source).
  def handle_event(
        "build-tap",
        %{"point" => point},
        %{assigns: %{my_turn: true, has_rolled: true}} = socket
      ) do
    assigns = socket.assigns
    build = assigns.build || %{moves: [], from: nil}
    from = Map.get(build, :from)
    ref = if point == "bar", do: :bar, else: String.to_integer(point)

    cond do
      from == nil and ref in build_sources(assigns) ->
        {:noreply, assign(socket, build: %{build | from: ref}, pending: nil)}

      from == nil ->
        {:noreply, socket}

      from != :bar and ref == from ->
        {:noreply, assign(socket, build: %{build | from: nil}, pending: nil)}

      true ->
        apply_build_move(socket, assigns, from, ref)
    end
  end

  def handle_event("build-tap", _point, socket), do: {:noreply, socket}

  # Chips under the board: a legal destination reachable from the picked
  # source (points, or "off" for a bear-off), as an alternative to board taps.
  def handle_event("build-dest", %{"dest" => dest}, socket) do
    assigns = socket.assigns

    if assigns.my_turn and assigns.has_rolled do
      build = assigns.build || %{moves: [], from: nil}
      from = Map.get(build, :from)
      target = if dest == "off", do: :off, else: String.to_integer(dest)

      if from, do: apply_build_move(socket, assigns, from, target), else: {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("build-undo", _, socket) do
    case socket.assigns.build do
      %{moves: moves} = build when moves != [] ->
        {:noreply, assign(socket, build: %{build | moves: Enum.drop(moves, -1), from: nil})}

      _ ->
        {:noreply, assign(socket, build: nil, pending: nil)}
    end
  end

  def handle_event("build-clear", _, socket) do
    {:noreply, assign(socket, build: nil, pending: nil)}
  end

  def handle_event("toggle-plays", _, socket) do
    {:noreply, assign(socket, show_plays: not socket.assigns.show_plays)}
  end

  def handle_event("note-change", %{"note" => note}, socket) do
    {:noreply, assign(socket, note: note)}
  end

  # ---- publish handlers (roll, turn, resign) ----

  def handle_event("publish-roll", %{"game_id" => game_id} = params, socket)
      when is_binary(game_id) do
    with row when not is_nil(row) <- game_row(game_id),
         true <- row.mover == socket.assigns.identity,
         {remaining, r_cur, r_next} <- publish_reveals(socket.assigns),
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
    with row when not is_nil(row) <- game_row(game_id),
         true <- row.mover == socket.assigns.identity,
         {turn, ""} <- Integer.parse(Map.get(params, "turn", "")),
         roll when is_binary(roll) and roll != "" <- Map.get(params, "roll"),
         moves when is_binary(moves) <- Map.get(params, "moves", ""),
         {remaining, r_cur, r_next} <- publish_reveals(socket.assigns),
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
    with row when not is_nil(row) <- game_row(game_id),
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

  def handle_event("replay-start", _, socket),
    do: {:noreply, assign(socket, replay: %{step: 0})}

  def handle_event("replay-prev", _, socket) do
    step = max(Map.get(socket.assigns.replay, :step), 1) - 1
    {:noreply, assign(socket, replay: %{step: step})}
  end

  def handle_event("replay-next", _, socket) do
    step = min(Map.get(socket.assigns.replay, :step), turns(socket.assigns) + 1) + 1
    {:noreply, assign(socket, replay: %{step: min(step, turns(socket.assigns))})}
  end

  def handle_event("replay-end", _, socket) do
    {:noreply, assign(socket, replay: %{step: turns(socket.assigns)})}
  end

  defp apply_build_move(socket, assigns, from, target) do
    case Enum.find(build_dests(assigns, from), fn {_die, to} -> to == target end) do
      nil ->
        {:noreply, socket}

      _ ->
        build = assigns.build || %{moves: [], from: nil}
        moves = Map.get(build, :moves, []) ++ [{from, target}]
        {:noreply, assign(socket, build: elect_moves(assigns, moves), pending: nil)}
    end
  end

  # "Elected" completion: once the tapped moves narrow the entry to exactly
  # one maximal play, the remaining moves of that play are forced — adopt its
  # full notation so the player just publishes. Otherwise the build continues.
  defp elect_moves(assigns, moves) do
    matches =
      Enum.filter(
        Engine.legal_plays(assigns.live_position, assigns.roll),
        fn play -> Enum.all?(moves, &(&1 in play)) end
      )

    case matches do
      [play] -> %{moves: play, from: nil}
      _ -> %{moves: moves, from: nil}
    end
  end

  def handle_info(:tick, socket) do
    {:noreply, socket}
  end

  # The mover's current reveal pair and dice, derived from their recoverable
  # chain, how many reveals they have left, and the opponent's published half.
  #
  # Only the SOCKET's own chain is ever derived here (role is pinned to this
  # identity), so a machine holding both players' secrets still never derives
  # the opponent's reveals. The opponent's half for this roll is always the
  # value they already announced, taken from the fold's opp_for_next — after
  # the fold has verified it — never recomputed from a locally-present key.
  defp my_reveals(assigns) do
    with game when not is_nil(game) <- assigns[:game],
         identity when is_binary(identity) <- assigns[:identity],
         role when is_binary(role) <- role_for(identity, game),
         name when is_binary(name) <- Catenary.id_for_key(identity),
         secret when is_binary(secret) <- Baobab.Identity.key(name, :secret),
         {:ok, gid} <- Base.decode16(game.game_id, case: :lower),
         remaining when is_integer(remaining) and remaining >= 2 <-
           Map.get(game, :remaining, %{}) |> Map.get(identity, @chain_length),
         chain when is_list(chain) <- ensure_chain(game, role, secret, gid),
         {r_cur, r_next} <- Chain.reveal_pair(chain, remaining),
         opp when is_binary(opp) and byte_size(opp) == 32 <- maybe_unhex(game.opp_for_next),
         [d1, d2] when d1 in 1..6 and d2 in 1..6 <- Chain.dice(r_cur, opp) do
      {r_cur, r_next, d1, d2}
    else
      _ -> :error
    end
  end

  defp role_for(identity, game) do
    cond do
      identity == Map.get(game, :challenger) -> "challenger"
      identity == Map.get(game, :accepter) -> "accepter"
      true -> nil
    end
  end

  # The reveal pair needed by the publish handlers: {remaining, r_cur, r_next}.
  # Like my_reveals/1 but returns the remaining count alongside the reveals
  # (no dice computation needed for publishing).
  defp publish_reveals(assigns) do
    with game when not is_nil(game) <- assigns[:game],
         identity when is_binary(identity) <- assigns[:identity],
         role when is_binary(role) <- role_for(identity, game),
         name when is_binary(name) <- Catenary.id_for_key(identity),
         secret when is_binary(secret) <- Baobab.Identity.key(name, :secret),
         {:ok, gid} <- Base.decode16(game.game_id, case: :lower),
         remaining when is_integer(remaining) and remaining >= 2 <-
           Map.get(game, :remaining, %{}) |> Map.get(identity, @chain_length),
         chain when is_list(chain) <- ensure_chain(game, role, secret, gid),
         {r_cur, r_next} <- Chain.reveal_pair(chain, remaining) do
      {remaining, r_cur, r_next}
    else
      _ -> :error
    end
  end

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

  defp warm_chain(assigns, game) do
    with role when is_binary(role) <- role_for(assigns.identity, game),
         name when is_binary(name) <- Catenary.id_for_key(assigns.identity),
         secret when is_binary(secret) <- Baobab.Identity.key(name, :secret),
         {:ok, gid} <- Base.decode16(game.game_id, case: :lower) do
      Task.start(fn -> ensure_chain(game, role, secret, gid) end)
    else
      _ -> :ok
    end

    assigns
  end

  # Our chain for this game, from the game-row cache. The ~10s scrypt build is
  # pre-warmed in the background on mount; a cold cache (rarely — e.g. the
  # roll click beating the warm task) builds now and backfills the row.
  defp ensure_chain(game, role, secret, gid) do
    case live_game(game.game_id) |> Chain.cache_get(role) do
      chain when is_list(chain) ->
        chain

      _ ->
        chain =
          Chain.seed_for(secret, gid, role)
          |> Chain.generate()

        Chain.cache_put(game.game_id, role, chain)
        chain
    end
  end

  defp live_game(game_id) do
    case :ets.lookup(:challenges, {:game, game_id}) do
      [{_, game}] -> game
      [] -> nil
    end
  end

  # ---- display derivation ----

  defp display_position(assigns) do
    {pos, actor} =
      case assigns.replay do
        %{step: 0} ->
          {Engine.initial(), live_actor(assigns.game)}

        %{step: step} when step > 0 ->
          case Enum.at(assigns.history, step - 1) do
            nil -> {assigns.live_position, live_actor(assigns.game)}
            item -> {item.after, item.player}
          end

        _ ->
          {assigns.live_position, live_actor(assigns.game)}
      end

    viewer_side(assigns, pos, actor)
  end

  # The board state on the viewer's live turn renders the moves being prepared
  # as if already made: a partial tap-build or a full play picked from the list
  # both read as the checkers having moved — a landing shows the mover's own
  # checker color, and a hit shows the knocked checker arriving on the far bar.
  # This preview only applies on the live frame: scrubbing to a past turn shows
  # that turn's stored position (with its own roll and highlights) even when
  # the viewer has already rolled their current turn.
  defp board_display(assigns) do
    if assigns.my_turn and assigns.has_rolled and live_frame?(assigns),
      do: {preview_pos(assigns), live_actor(assigns.game)},
      else: display_position(assigns)
  end

  # The moves awaiting publish, whether entered by tapping (`build`) or picked
  # from the full-play list (`pending`): both preview the same way.
  defp preview_moves(assigns) do
    case Map.get(assigns, :build) do
      %{moves: moves} when is_list(moves) ->
        moves

      _ ->
        case Map.get(assigns, :pending) do
          play when is_list(play) -> play
          _ -> []
        end
    end
  end

  defp preview_pos(assigns),
    do: Engine.apply(assigns.live_position, preview_moves(assigns))

  # The game's mover is the actor whose frame the fold's live position is in
  # (the current mover during play, the next roller while still opening).
  defp live_actor(game), do: Map.get(game, :mover) || Map.get(game, :challenger)

  # Every position on screen is drawn from the viewer's side of the table,
  # never the turn author's: a playing viewer who is not the frame actor gets
  # the mirrored view, so their own checkers always sit on the near rail and
  # the colors stay consistent (viewer dark, opponent light) across live play
  # and the whole replay. Non-participants keep the stored frame. The actor
  # (frame owner) travels with the position for the board render/colors.
  defp viewer_side(assigns, pos, actor) do
    if mirror_viewer?(assigns[:identity], assigns.game, actor),
      do: {Engine.mirror(pos), actor},
      else: {pos, actor}
  end

  defp mirror_viewer?(identity, game, actor) when is_binary(identity) do
    accepter = Map.get(game, :accepter)
    is_binary(accepter) and identity in [game.challenger, accepter] and identity != actor
  end

  defp mirror_viewer?(_identity, _game, _actor), do: false

  # The participant the position's actor (near rail) represents: the viewer
  # when they are playing, else the current mover.
  defp actor_role(game, identity) do
    cond do
      identity == game.challenger -> "challenger"
      identity == game.accepter -> "accepter"
      Map.get(game, :mover) == game.challenger -> "challenger"
      true -> "accepter"
    end
  end

  # The display-frame (near/far) a named participant sits in, from the
  # viewer-frame position.
  defp participant_role(game, identity, role) do
    if role == actor_role(game, identity), do: :actor, else: :opponent
  end

  # pips/bar/off for a participant, from the viewer-frame position.
  defp rail_stats(position, :actor),
    do: {Engine.pips(position, :actor), position.bar, position.off}

  defp rail_stats(position, :opponent),
    do: {Engine.pips(position, :opponent), position.opp_bar, position.opp_off}

  defp display_roll(assigns) do
    live = turns(assigns)

    case assigns.replay do
      %{step: step} when is_integer(step) and step > 0 and step <= live ->
        item = Enum.at(assigns.history, step - 1)
        if item, do: item.roll

      %{step: 0} when not assigns.opening ->
        if assigns.has_rolled, do: assigns.roll

      _ ->
        nil
    end
  end

  defp replay_step(replay), do: Map.get(replay, :step, 0)

  # The scrubber sits on its last step — every folded turn replayed. That is
  # the same frame as the live position, so the viewer's own roll, the move
  # entry surface, and the live build preview apply; any step below it is a
  # scrubbed past frame where the local roll must stand aside for the fold's
  # stored dice.
  defp live_frame?(assigns), do: replay_step(assigns.replay) == turns(assigns)

  defp turns(assigns), do: length(assigns.history)

  # The legal plays from the live position, as move lists. Position is in
  # the mover's frame exactly when it's our turn, so plays apply directly.
  # When a board build is in progress the list is TRIMMED to the plays that
  # still contain every move already tapped, so picking from the list can
  # never contradict the partial move — and once a build narrows to a single
  # completion, only that play remains.
  defp legal_plays_for(assigns) do
    legal =
      case assigns.roll do
        {d1, d2} -> Engine.legal_plays(assigns.live_position, {d1, d2})
        _ -> []
      end

    case assigns.build do
      %{moves: moves} when moves != [] ->
        Enum.filter(legal, fn play -> Enum.all?(moves, &(&1 in play)) end)

      _ ->
        legal
    end
  end

  # A stand (pass) is only a play when nothing can move at all.
  defp stand_only?(assigns), do: legal_plays_for(assigns) == [[]]

  defp play_cls(assigns, :pass), do: play_cls_base(assigns.pending == :pass)
  defp play_cls(assigns, play), do: play_cls_base(assigns.pending == play)

  defp play_cls_base(selected) do
    sel =
      if selected,
        do: " border-sky-500 dark:border-sky-400 text-sky-700 dark:text-sky-300",
        else: " border-slate-300 dark:border-slate-600 text-slate-700 dark:text-slate-300"

    "px-2.5 py-1 rounded border bg-slate-50 dark:bg-slate-800 text-xs font-mono hover:border-sky-400" <>
      sel
  end

  defp resign_badge_cls(%{pending: :resign} = _assigns),
    do: "bg-red-600 text-white dark:bg-red-500 dark:text-slate-900"

  defp resign_badge_cls(_assigns),
    do:
      "bg-slate-200 text-slate-500 dark:bg-slate-700 dark:text-slate-400 hover:bg-red-100 hover:text-red-600 dark:hover:bg-red-900/40 dark:hover:text-red-400"

  defp moves_for(assigns) do
    if Map.get(assigns, :build) != nil do
      move_string(assigns.build.moves)
    else
      case assigns.pending do
        play when is_list(play) -> Notation.turn(play)
        _ -> ""
      end
    end
  end

  # A board-built play publishes in the engine's canonical order (sorted —
  # each move's die is implied by its geometry), so the fold's membership
  # check against the sorted `legal_plays/2` list always succeeds regardless
  # of the order the player tapped the moves in.
  defp move_string(moves) do
    moves
    |> Engine.canonicalize()
    |> Notation.turn()
  end

  # Ready to publish when a complete play is selected: either a full-play list
  # pick, or a board build whose moves form a legal maximal play.
  defp ready_to_publish?(assigns) do
    cond do
      Map.get(assigns, :build) != nil ->
        Engine.legal_play?(assigns.live_position, assigns.roll, assigns.build.moves)

      assigns.pending != nil ->
        true

      true ->
        false
    end
  end

  # ---- board move entry ----
  #
  # The viewer's own turn board is their own frame, so a build is just a list
  # of `{from, to}` moves replayed onto the live position; the running
  # position and remaining dice derive from it each render.
  defp build_moves(assigns), do: Map.get(assigns.build || %{moves: []}, :moves, [])

  defp build_pos(assigns), do: Engine.apply(assigns.live_position, build_moves(assigns))

  # The dice not yet consumed. Each built move implies the die it used by its
  # geometry, so a move entered from either die cancels exactly that one.
  defp build_rem(assigns) do
    case assigns.roll do
      {d1, d2} ->
        Enum.reduce(build_moves(assigns), [d1, d2], fn mv, rem ->
          remove_one_die(rem, die_for_move(mv))
        end)

      _ ->
        []
    end
  end

  defp die_for_move({:bar, to}), do: 25 - to
  defp die_for_move({from, :off}), do: from
  defp die_for_move({from, to}), do: from - to

  defp remove_one_die(list, die) do
    {matching, rest} = Enum.split_with(list, &(&1 == die))

    case matching do
      [] -> rest
      [_ | more] -> more ++ rest
    end
  end

  # Every legal single move available on the running position with the dice
  # left — the "reduced legal list": on the board only points that appear
  # here glow as sources.
  defp build_options(assigns) do
    pos = build_pos(assigns)

    for die <- Enum.uniq(build_rem(assigns)),
        mv <- Engine.moves_for(pos, die),
        do: {die, mv}
  end

  defp build_sources(assigns),
    do:
      build_options(assigns)
      |> Enum.map(fn {_die, mv} -> elem(mv, 0) end)
      |> Enum.uniq()

  defp build_dests(assigns, from),
    do: for({die, mv} <- build_options(assigns), elem(mv, 0) == from, do: {die, elem(mv, 1)})

  # Chips offered below the board for the picked source (the destination of
  # each legal move from it, "off" for a bear-off), labelled in Magriel.
  defp reach_chips(assigns) do
    case assigns.build && Map.get(assigns.build, :from) do
      nil ->
        []

      from ->
        build_dests(assigns, from)
        |> Enum.map(fn {_die, to} ->
          %{dest: if(to == :off, do: "off", else: "#{to}"), label: Notation.move(from, to)}
        end)
    end
  end

  # The final, canonical play currently selected — by a full-play-list pick or
  # by a completed board build — or nil when nothing is chosen yet. This is
  # exactly what `moves_for/1` publishes, so the summary and the log line never
  # drift apart.
  defp elected_play(assigns) do
    cond do
      Map.get(assigns, :build) != nil and build_complete?(assigns) ->
        Engine.canonicalize(assigns.build.moves)

      is_list(assigns.pending) ->
        assigns.pending

      true ->
        nil
    end
  end

  # "you: 143 pips · 0 on bar · 5 off" for the selected play — the effect the
  # move has on the live position, in the mover's (viewer's) frame.
  defp effect_line(assigns, play, role) do
    {pips, bar, off} = rail_stats(Engine.apply(assigns.live_position, play), role)
    "#{pips} pips · #{bar} bar · #{off} off"
  end

  # The current notation of a board build: empty before any move, the partial
  # (canonical, sorted) notation while building, and the elected final
  # notation once the tap sequence narrows to a single maximal play.
  defp build_notation(assigns) do
    if assigns.build, do: move_string(assigns.build.moves), else: ""
  end

  defp build_complete?(assigns), do: assigns.build != nil and build_options(assigns) == []

  # The board-mode stand: nothing can move and nothing has been tapped yet
  # (a build that has consumed dice but is unable to continue is complete,
  # not a pass).
  defp build_stand?(assigns) do
    build_options(assigns) == [] and build_moves(assigns) == []
  end

  defp roll_string(nil), do: ""
  defp roll_string({d1, d2}), do: Game.roll_string(d1, d2)

  defp turn_note(assigns) do
    cond do
      assigns.roll_error ->
        {:safe,
         "<span class=\"text-xs text-red-500 font-semibold\">could not derive your roll — reload to recover</span>"}

      active_replay?(assigns.replay) ->
        note_span(turn_caption(assigns))

      replay_step(assigns.replay) == 0 ->
        case opener_note(assigns) do
          n when is_binary(n) and n != "" -> note_span(n)
          _ -> {:safe, ""}
        end

      true ->
        {:safe, ""}
    end
  end

  defp note_span(text) do
    {:safe, "<span class=\"text-xs text-slate-400 dark:text-slate-600\">" <> text <> "</span>"}
  end

  # The resolved opening, surfaced as a "turn 0" game note (only reachable by
  # stepping the replay back to the start) rather than a persistent banner.
  defp opener_note(assigns) do
    game = assigns.game

    case Map.get(game, :opener) do
      %{starter: starter, dice: [d_c, d_a]} when is_integer(d_c) and is_integer(d_a) ->
        "turn 0: Opening resolved — #{compact_name(starter, assigns.aliases)} starts (#{d_c} vs #{d_a})."

      _ ->
        ""
    end
  end

  defp active_replay?(%{step: step}), do: step > 0
  defp active_replay?(_), do: false

  defp turn_caption(assigns) do
    case assigns.replay do
      %{step: step} when step > 0 ->
        case Enum.at(assigns.history, step - 1) do
          nil ->
            "turn #{step}: dice sealed until the player rolls"

          item ->
            replay_caption(item, assigns.aliases)
        end

      _ ->
        if assigns.my_turn and not assigns.has_rolled,
          do: "dice sealed until you roll",
          else: "dice shown when a player rolls"
    end
  end

  defp replay_caption(item, aliases) do
    caption =
      case Map.get(item, :type) do
        "resign" ->
          "turn #{item.turn}: #{compact_name(item.player, aliases)} resigns"

        _ ->
          moves_str =
            case Map.get(item, :moves) do
              m when is_binary(m) and m != "" -> " · #{m}"
              _ -> " · no legal moves"
            end

          "turn #{item.turn}: #{compact_name(item.player, aliases)} rolled #{item.roll}" <>
            moves_str
      end

    case Map.get(item, :note) do
      n when is_binary(n) and n != "" -> caption <> " — \u201c#{n}\u201d"
      _ -> caption
    end
  end

  # A flat, real-board layout: four quadrants of six triangular points around
  # a central bar. The far (opponent-facing) row runs 24..13 top-down toward
  # the centre; the near (actor-facing) row 12..1 mirrors it. Positive counts
  # are the actor's checkers, negative counts the opponent's, each stacked
  # from its triangle's base toward the tip. Colors are per player, not per
  # side: the challenger always dark, the accepter always light, so when the
  # accepter views from their own rail the near checkers render light.
  #
  # On the viewer's turn the board becomes the move entry surface: the top
  # checkers of the picked source (and, before anything is picked, of each
  # pickable source) carry rings, legal destinations have their triangles'
  # tips glowing, and every cell is wired to `build-tap`; the position itself
  # shows the built moves as already made. In replay, `turn_flash/2` resolves
  # the net diff of the selected turn (from the fold's per-move frames) and
  # renders it on the checkers in the viewer's display frame.
  defp board({position, actor}, assigns, cid) do
    actor_is_challenger = actor_role(assigns.game, assigns.identity) == "challenger"
    hl = board_highlights(assigns, actor)

    {:safe,
     "<div class=\"w-fit mx-auto select-none\">" <>
       "<div class=\"rounded-xl bg-gradient-to-b from-amber-600 via-amber-700 to-amber-800 p-2 shadow-lg ring-1 ring-black/30\">" <>
       "<div class=\"relative rounded-lg overflow-hidden\">" <>
       board_row(position, 24..13//-1, :down, position.opp_bar, :opponent, position.opp_off, %{
         actor_is_challenger: actor_is_challenger,
         hl: hl,
         bar_ref: :opp_bar,
         cid: cid
       }) <>
       board_row(position, 12..1//-1, :up, position.bar, :actor, position.off, %{
         actor_is_challenger: actor_is_challenger,
         hl: hl,
         bar_ref: :own_bar,
         cid: cid
       }) <>
       "<div class=\"absolute inset-x-0 top-1/2 h-px bg-black/25 pointer-events-none\"></div>" <>
       "</div></div></div>"}
  end

  defp board_row(position, points, dir, on_bar, owner, off_count, ctx) do
    [half1, half2] = Enum.chunk_every(Enum.to_list(points), 6)
    %{actor_is_challenger: actor_is_challenger, hl: hl, bar_ref: bar_ref, cid: cid} = ctx

    "<div class=\"flex\">" <>
      Enum.map_join(
        half1,
        &point_cell(
          Map.get(position.points, &1, 0),
          &1,
          dir,
          actor_is_challenger,
          cell_opts(&1, hl, cid)
        )
      ) <>
      bar_cell(on_bar, owner, actor_is_challenger, bar_opts(bar_ref, hl, cid)) <>
      Enum.map_join(
        half2,
        &point_cell(
          Map.get(position.points, &1, 0),
          &1,
          dir,
          actor_is_challenger,
          cell_opts(&1, hl, cid)
        )
      ) <>
      off_cell(off_count, owner, actor_is_challenger, dir) <>
      "</div>"
  end

  # What the board render must draw on top of the displayed position: the
  # replay diff (stacks + bar changed across the selected turn, in the
  # viewer's frame) and a live preview diff (the moves built so far, drawn
  # exactly like an elected turn — landings glow, sources ghost, knocked
  # checkers arrive on the bar), plus the edit highlights (slim source rings,
  # glowing destination tips, and the tap wiring) when the viewer is building
  # a move.
  defp board_highlights(assigns, actor) do
    {t_gained, t_lost} = turn_flash(assigns, actor)
    {b_gained, b_lost} = preview_diff(assigns)

    %{
      diff: %{gained: t_gained ++ b_gained, lost: t_lost ++ b_lost},
      edit: board_edit(assigns)
    }
  end

  # Direction-aware diff of the moves awaiting publish (tap-built or list-picked).
  # The board already renders the position AFTER those moves, so this is the
  # same net-count diff the replay uses: landings light green, sources the
  # checkers left ghost, and a hit shows the knocked checker arriving on the
  # far bar — no hand-rolled per-move hit detection needed. Mirroring is
  # skipped because the board is in the viewer's own frame when it is their
  # turn. Only the live frame diffs: a scrubbed past turn shows the replay's
  # own diff, not the pending build's.
  defp preview_diff(assigns) do
    if assigns.my_turn and assigns.has_rolled and live_frame?(assigns),
      do: turn_diff(assigns.live_position, preview_pos(assigns), false),
      else: {[], []}
  end

  defp put_ref(list, nil), do: list
  defp put_ref(list, ref), do: [ref | list]

  defp board_edit(assigns) do
    if assigns.my_turn and assigns.has_rolled and live_frame?(assigns) do
      build = assigns.build || %{moves: [], from: nil}
      from = Map.get(build, :from)

      %{
        from: display_ref(from),
        sources: Enum.map(build_sources(assigns), &display_ref/1),
        dests: display_dests(assigns, from)
      }
    end
  end

  # Display refs for the legal landings of the picked source (or [] when no
  # source is selected yet).
  defp display_dests(assigns, from) when is_integer(from) or from == :bar,
    do: Enum.map(build_dests(assigns, from), fn {_die, t} -> t end)

  defp display_dests(_assigns, _from), do: []

  # Display-space refs: 1..24 point numbers as rendered, :own_bar / :opp_bar
  # for the near/far bar cells. The edit surface is always in the viewer's
  # own frame (it is their turn), so engine refs map straight over. A nil
  # (no source picked, or a bear-off destination) renders no highlight ref.
  defp display_ref(nil), do: nil
  defp display_ref(:bar), do: :own_bar
  defp display_ref(:off), do: nil
  defp display_ref(p) when is_integer(p), do: p

  # The points a whole turn actually changed, tagged by net direction — gained
  # (more checkers now: light its stack) vs lost (fewer: mark the gap) —
  # computed by diffing the turn's first frame against its last (both in the
  # mover's frame), then translated into the viewer's display frame so the
  # highlight sits on the same cells the viewer elected had they just made the
  # move. Same diff semantics as the publish election, applied to the fold's
  # per-turn history. Only scrubbed past turns diff: at step == the live turn
  # count the position is current, so the board shows no replay highlights.
  defp turn_flash(assigns, actor) do
    live = turns(assigns)

    case assigns.replay do
      %{step: step} when is_integer(step) and step > 0 and step <= live ->
        item = Enum.at(assigns.history, step - 1)
        replay_flash(item, assigns, actor)

      _ ->
        {[], []}
    end
  end

  defp replay_flash(nil, _assigns, _actor), do: {[], []}

  defp replay_flash(%{frames: [_ | _] = frames}, assigns, actor) do
    f0 = List.first(frames)
    f1 = List.last(frames)
    turn_diff(f0, f1, mirror_viewer?(assigns[:identity], assigns.game, actor))
  end

  defp replay_flash(_item, _assigns, _actor), do: {[], []}

  defp turn_diff(f0, f1, mirror?) do
    t = if mirror?, do: &mirror_ref/1, else: &display_ref/1

    deltas =
      ((Map.keys(f0.points) ++ Map.keys(f1.points))
       |> Enum.uniq()
       |> Enum.map(fn p -> {Map.get(f1.points, p, 0) - Map.get(f0.points, p, 0), p} end)) ++
        [{f1.bar - f0.bar, :bar}, {f1.opp_bar - f0.opp_bar, :opp_bar}]

    {gained, lost} =
      Enum.reduce(deltas, {[], []}, fn
        {delta, _p}, {g, l} when delta == 0 ->
          {g, l}

        {delta, p}, {g, l} when p == :opp_bar ->
          # Already in display space in both views: a hit puts the checker on
          # the opponent's bar, which is the same far rail whichever side the
          # viewer sits on.
          if delta > 0, do: {put_ref(g, :opp_bar), l}, else: {g, put_ref(l, :opp_bar)}

        {delta, p}, {g, l} when delta > 0 ->
          {put_ref(g, t.(p)), l}

        {delta, p}, {g, l} when delta < 0 ->
          {g, put_ref(l, t.(p))}
      end)

    {gained, lost}
  end

  # The mover's own checker viewed from the opponent's rail: source and
  # destination swap side, so a mover-frame point p becomes display 25-p and
  # the mover's entries (bar) / bear-offs (off) move to the far bar cells.
  defp mirror_ref(:bar), do: :opp_bar
  defp mirror_ref(:off), do: nil
  defp mirror_ref(p) when is_integer(p), do: 25 - p

  defp cell_opts(p, hl, cid) do
    edit = hl.edit

    clickable? =
      is_map(edit) and
        (p in edit.sources or p in edit.dests or p == edit.from)

    %{
      source: source_mark(hl, p),
      dest: is_map(edit) and p in edit.dests,
      gained: p in hl.diff.gained,
      lost: p in hl.diff.lost,
      click:
        if(clickable?,
          do: " phx-target=\"#{cid}\" phx-click=\"build-tap\" phx-value-point=\"#{p}\"",
          else: ""
        )
    }
  end

  # The source-selection affordance for a point, in point-to-point form: only
  # the top checker of a source's stack is marked (see `stack`), never the
  # whole triangle. The picked source is sky-ringed; while nothing is picked
  # no rings appear. Once a source is selected, the picked top checker and
  # the glowing landings remain, so the board stays clean.
  defp source_mark(hl, p) do
    case hl.edit do
      %{from: ^p} -> :picked
      _ -> nil
    end
  end

  defp bar_opts(ref, hl, cid) do
    edit = hl.edit

    tri =
      if is_map(edit) and edit.from == ref,
        do: " ring-2 ring-sky-500",
        else: ""

    clickable? =
      is_map(edit) and
        (ref in edit.sources or ref in edit.dests or ref == edit.from)

    %{
      rect: tri,
      gained: ref in hl.diff.gained,
      lost: ref in hl.diff.lost,
      click:
        if(clickable?,
          do: " phx-target=\"#{cid}\" phx-click=\"build-tap\" phx-value-point=\"bar\"",
          else: ""
        )
    }
  end

  defp dice_pips(nil), do: empty_pips()
  defp dice_pips(roll) when is_binary(roll), do: pip_pair(pips_from_roll(roll))
  defp dice_pips({d1, d2}), do: pip_pair({d1, d2})

  defp pips_from_roll(roll) do
    case String.split(roll, "-") |> Enum.map(&String.to_integer/1) do
      [a, b] -> {a, b}
      _ -> {1, 1}
    end
  end

  defp empty_pips do
    {:safe,
     "<div class=\"flex gap-1.5\">" <>
       "<div class=\"w-9 h-9 rounded border border-slate-300 dark:border-slate-600 flex items-center justify-center text-slate-300 dark:text-slate-700 font-bold\"></div>" <>
       "<div class=\"w-9 h-9 rounded border border-slate-300 dark:border-slate-600 flex items-center justify-center text-slate-300 dark:text-slate-700 font-bold\"></div>" <>
       "</div>"}
  end

  defp pip_pair({d1, d2}) do
    {:safe,
     "<div class=\"flex gap-1.5\">" <>
       pip(d1) <> pip(d2) <> "</div>"}
  end

  # The single opening die beside each player's name during the rollout:
  # opener.dice is [d_challenger, d_accepter] once the round resolves (the
  # challenger's die is knowable the instant they publish, seeded by the
  # accepter's already known half; the accepter's die lands with their own
  # publication). The opener is nil before any roll or after a tie clears the
  # round. Once a starter is decided the opening caption takes over and these
  # leave the play area.
  defp opening_pip(game, role) when role in ["challenger", "accepter"] do
    case Map.get(game, :phase, :opening) do
      :opening ->
        d =
          case {role, Map.get(game, :opener)} do
            {"challenger", %{dice: [d_c, _]}} when is_integer(d_c) -> d_c
            {"accepter", %{dice: [d_c, d_a]}} when is_integer(d_c) and is_integer(d_a) -> d_a
            _ -> nil
          end

        {:safe,
         "<div class=\"flex gap-1.5\">" <> if(d, do: pip(d), else: empty_pip()) <> "</div>"}

      _ ->
        {:safe, ""}
    end
  end

  defp opening_pip(_game, _role), do: {:safe, ""}

  defp empty_pip do
    "<div class=\"w-9 h-9 rounded border border-dashed border-slate-300 dark:border-slate-600 bg-slate-50 dark:bg-slate-800/40\"></div>"
  end

  defp pip(d) do
    "<div class=\"w-9 h-9 rounded border border-amber-400 bg-slate-50 dark:bg-slate-800 flex items-center justify-center text-amber-700 dark:text-amber-300 font-bold text-lg\">" <>
      "#{d}</div>"
  end

  # Compact ~name for score labels; long aliases truncate instead of
  # blowing out the strip.
  defp compact_name(id, aliases) when is_binary(id) do
    name = Display.short_id(id, aliases)

    if String.length(name) > 10, do: String.slice(name, 0..9) <> "…", else: name
  end

  defp compact_name(_, _), do: "opp"

  # Triangular point with its stack of checkers leaning from the base (the
  # outer edge) toward the bar. A 24px band along the outer edge is carved out
  # of the triangle so the point number sits on wood, away from the checkers;
  # the apex still reaches the opposite rail. `opts` carries the edit
  # affordances (`source` top-checker mark, `dest` triangle-tip glow) and,
  # while editing, the `phx-click`/`phx-value-point` wiring for tap-to-move.
  # A destination glow sits on its own wrapper so the drop-shadow is not
  # clipped away by the triangle's clip-path.
  defp point_cell(count, p, dir, actor_is_challenger, opts) do
    clip_poly =
      if dir == :up,
        do: "polygon(0 86.4%, 100% 86.4%, 50% 0)",
        else: "polygon(0 13.6%, 100% 13.6%, 50% 100%)"

    point = if rem(p, 2) == 0, do: "bg-emerald-800", else: "bg-amber-100"
    glow = if opts[:dest], do: " drop-shadow-[0_0_8px_rgba(56,189,248,0.9)]", else: ""
    edge = if dir == :up, do: "bottom-0 pb-6", else: "top-0 pt-6"
    cursor = if opts[:click] == "", do: "", else: " cursor-pointer"

    "<div class=\"relative w-10 h-44#{cursor}\"#{opts[:click]}>" <>
      "<div class=\"absolute inset-0#{glow}\">" <>
      ~s(<div class="absolute inset-0 #{point}" style="clip-path: #{clip_poly}"></div>) <>
      "</div>" <>
      "<div class=\"absolute inset-x-0 #{edge} flex justify-center\">" <>
      stack(count, dir, actor_is_challenger, opts[:gained], opts[:lost], opts[:source]) <>
      "</div>" <>
      point_number(p, dir) <>
      "</div>"
  end

  # The point number sits on the carved outer band (opposite the bar) as a
  # small high-contrast chip: atop the far row points, beneath the near row
  # points, never in the checkers' lane.
  defp point_number(p, dir) do
    edge = if dir == :down, do: "top-0", else: "bottom-0"

    "<div class=\"absolute inset-x-0 #{edge} h-6 flex items-center justify-center select-none pointer-events-none\">" <>
      "<span class=\"rounded bg-black/30 px-1 text-[10px] font-mono font-semibold leading-none text-white/90 shadow-sm\">" <>
      "#{p}</span></div>"
  end

  defp stack(count, dir, actor_is_challenger, gained, lost, source) do
    col = if dir == :up, do: "justify-end", else: "justify-start"
    n = abs(count)
    owner = if count > 0, do: :actor, else: :opponent

    # The departed checker's slot sits at the tip of the point — the end
    # nearest the board centre where checkers enter and leave. On the top
    # rail (dir = :down, justify-start) the tip is the last DOM child; on
    # the bottom rail (dir = :up, justify-end) it is the first.
    ghost_slots = if lost, do: 1, else: 0
    visible = min(n, 5 - ghost_slots)
    overflow = max(n - 5, 0)

    # The ghost always represents the actor's departed checker, so it uses
    # the actor's colour regardless of the (possibly mirrored) point count.
    ghost = if(lost, do: ghost_pip(actor_is_challenger), else: "")

    overflow_el = stack_overflow_el(overflow, owner, actor_is_challenger)

    # On the bottom rail (dir = :up, justify-end) items stack bottom-to-top:
    # first DOM child at the tip (near bar), last at the base (away from bar).
    # The departed checker's ghost belongs at the tip, so it goes first.
    # On the top rail (dir = :down, justify-start) items stack top-to-bottom:
    # first DOM child at the base (away from bar), last at the tip (near bar),
    # so the ghost goes last.
    checkers_el = checkers(visible, owner, actor_is_challenger, gained, source, dir)

    # Overflow badge always sits on the outside (base) of the point — away
    # from the bar. For :down (top rail, justify-start) that is the first
    # DOM child; for :up (bottom rail, justify-end) it is the last.
    {first_el, second_el, third_el} =
      if dir == :down,
        do: {overflow_el, checkers_el, ghost},
        else: {ghost, checkers_el, overflow_el}

    "<div class=\"flex flex-col items-center #{col}\">" <>
      first_el <>
      second_el <>
      third_el <>
      "</div>"
  end

  defp stack_overflow_el(overflow, owner, actor_is_challenger) when overflow > 0 do
    dark? = if(owner == :actor, do: actor_is_challenger, else: not actor_is_challenger)
    body = if(dark?, do: "bg-slate-700", else: "bg-white")
    ring = if(dark?, do: "ring-amber-300/90", else: "ring-slate-900")
    badge_bg = if(dark?, do: "bg-slate-700", else: "bg-white/90")
    badge_text = if(dark?, do: "text-slate-100", else: "text-slate-900")

    "<div class=\"relative inline-flex\">" <>
      "<div class=\"w-6 h-6 rounded-full #{body} ring-inset ring-2 #{ring} shadow-sm\"></div>" <>
      "<span class=\"absolute inset-[2px] flex items-center justify-center rounded-full #{badge_bg} text-[10px] font-mono font-semibold #{badge_text} shadow\">+#{overflow}</span>" <>
      "</div>"
  end

  defp stack_overflow_el(_, _, _), do: ""

  # Per-player colors: dark when the stack's owner is the challenger, light
  # when the accepter — regardless of which side of the table the viewer
  # sits on. `actor_is_challenger` maps the near rail to its fixed player.
  # The `source` mark (:picked / :idle) rings only the top checker of the
  # pile — the checker that a point-to-point pick would move — never the
  # whole column.
  defp checkers(n, owner, actor_is_challenger, gained, mark, dir) when n > 0 do
    dark? = if owner == :actor, do: actor_is_challenger, else: not actor_is_challenger
    # Highlight the checker closest to the bar (center): on the bottom rail
    # (dir = :up, justify-end) that is checker 1; on the top rail (dir = :down,
    # justify-start) it is the last visible checker.
    hi_idx = if dir == :down, do: min(n, 6), else: 1

    Enum.map_join(1..min(n, 6), fn i ->
      checker(dark?, if(i == hi_idx, do: gained, else: false), if(i == hi_idx, do: mark, else: nil))
    end)
  end

  defp checkers(_, _, _, _, _, _), do: ""

  defp overflow_badge(extra) when extra > 0,
    do:
      "<span class=\"rounded bg-white/90 px-1 text-[10px] font-mono font-semibold text-slate-900 shadow\">+#{extra}</span>"

  defp overflow_badge(_), do: ""

  # A lit checker marks a stack that just gained (replay turn) or is about to
  # receive (partial build): the checker keeps its own body color (so a lit
  # opponent checker still reads as opponent, not as one of yours) and is rung
  # with a single bright green ring and glow — the same highlight color for
  # dark and light checkers alike, chosen to pop against both bodies and the
  # wood. A `source` mark overrides it on that one checker: sky for the picked
  # source, a quiet emerald for the still-pickable ones.
  defp checker(dark?, gained, mark) do
    body = if dark?, do: "bg-slate-700", else: "bg-white"

    cond do
      mark == :picked ->
        "<div class=\"w-6 h-6 rounded-full #{body} ring-inset ring-2 ring-sky-500 shadow-[0_0_0_2px_rgba(14,165,233,0.5),0_0_12px_2px_rgba(56,189,248,0.9)]\"></div>"

      gained ->
        "<div class=\"w-6 h-6 rounded-full #{body} ring-inset ring-[3px] ring-emerald-400 shadow-[0_0_0_2px_rgba(16,185,129,0.6),0_0_12px_2px_rgba(16,185,129,0.85)]\"></div>"

      true ->
        ring = if dark?, do: "ring-amber-300/90", else: "ring-slate-900"

        "<div class=\"w-6 h-6 rounded-full #{body} ring-inset ring-2 #{ring} shadow-sm\"></div>"
    end
  end

  # The empty echo of a checker that is no longer here (replay source, or a
  # partial build's picked chip): a translucent dashed outline over a soft fill
  # matching the actor's checker colour. Dark ghosts use a slate interior so
  # they read as departed dark checkers; light ghosts use amber. The dashed
  # border keeps them distinct from real checkers.
  defp ghost_pip(actor_is_challenger) do
    dark? = actor_is_challenger

    {border, bg, shadow} =
      if dark? do
        {"border-slate-400", "bg-slate-700/40",
         "shadow-[0_0_0_1px_rgba(100,116,139,0.6),0_0_6px_0px_rgba(148,163,184,0.45)]"}
      else
        {"border-amber-300", "bg-amber-100/40",
         "shadow-[0_0_0_1px_rgba(146,64,14,0.6),0_0_6px_0px_rgba(255,237,213,0.45)]"}
      end

    "<div class=\"w-6 h-6 rounded-full border-2 border-dashed #{border} #{bg} #{shadow}\"></div>"
  end

  defp bar_cell(on_bar, owner, actor_is_challenger, opts) do
    ghost_slots = if opts[:lost], do: 1, else: 0
    pips = min(on_bar, 6 - ghost_slots)
    cursor = if opts[:click] == "", do: "", else: " cursor-pointer"

    "<div class=\"w-10 h-44 bg-amber-950 flex flex-col items-center justify-center gap-px #{opts[:rect]}#{cursor}\"#{opts[:click]}>" <>
      checkers(pips, owner, actor_is_challenger, opts[:gained], nil, :up) <>
      overflow_badge(on_bar - pips) <>
      if(opts[:lost], do: ghost_pip(actor_is_challenger), else: "") <> "</div>"
  end

  # Bear-off tray: a narrow column to the right of the home board where
  # checkers are stacked on edge (thin horizontal bars) rising from the
  # bottom — the classic backgammon look of coins in a tray. Each checker
  # is a slim rounded bar in the player's colour with a subtle depth ring.
  # The tray fills from the bottom as checkers are borne off.
  # Hidden entirely when the player has no borne-off checkers.
  defp off_cell(off_count, owner, actor_is_challenger, dir) do
    dark? = if owner == :actor, do: actor_is_challenger, else: not actor_is_challenger
    pips = min(off_count, 15)
    body = if dark?, do: "bg-slate-800", else: "bg-white"
    ring = if dark?, do: "ring-slate-600/80", else: "ring-slate-300"
    col = if dir == :up, do: "justify-end", else: "justify-start"

    checkers_html =
      if pips > 0,
        do:
          for(
            _ <- 1..pips//1,
            into: "",
            do:
              "<div class=\"w-7 h-[5px] rounded-sm #{body} ring-1 #{ring} shadow-sm mb-px\"></div>"
          ),
        else: ""

    "<div class=\"w-10 h-44 rounded-r-lg border-l border-amber-800/40 bg-amber-950/50 flex flex-col items-center #{col}\">" <>
      checkers_html <>
      "</div>"
  end

  defp maybe_unhex(nil), do: nil
  defp maybe_unhex(bin) when is_binary(bin) and byte_size(bin) == 32, do: bin

  defp maybe_unhex(hex) when is_binary(hex) do
    case Base.decode16(hex, case: :lower) do
      {:ok, bin} when byte_size(bin) == 32 -> bin
      _ -> nil
    end
  end
end
