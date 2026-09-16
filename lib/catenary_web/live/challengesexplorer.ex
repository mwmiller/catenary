defmodule Catenary.Live.ChallengesExplorer do
  @moduledoc """
  LiveComponent rendering the backgammon challenges area.

  Reads the `:challenges` index table and shows games filtered by a tab
  toggle:

  * **Open** — challenges awaiting an accepter (incl. the viewer's own, which
    they may withdraw).
  * **Running** — accepted, ongoing games.

  Within each view the interactions shown are decided purely by the viewer's
  involvement with the game: accept appears when the game is open to the
  viewer (`to` is nil or the viewer), withdraw appears for the viewer's own
  still-open challenges, and a running game offers play, await or spectate
  depending on whether the viewer is a party and whose turn it is (the
  challenger moves on even turn counts, the accepter on odd).
  """
  use Phoenix.LiveComponent
  alias Catenary.Display

  @spectate_glyph "⊙"

  @game_actions %{
    play: %{
      glyph: "▶",
      title: "Play your move",
      cls:
        "rounded-md bg-slate-800 hover:bg-slate-700 active:bg-slate-900 dark:bg-slate-200 dark:hover:bg-slate-100 dark:active:bg-slate-300 text-white dark:text-slate-900 text-sm font-semibold px-2 py-1 shadow-sm transition-colors"
    },
    await: %{
      glyph: "⏱",
      title: "Your game — waiting for the opponent",
      cls:
        "rounded-md border border-slate-400 dark:border-slate-600 text-slate-500 dark:text-slate-300 text-sm px-2 py-1 transition-colors"
    },
    spectate: %{
      glyph: @spectate_glyph,
      title: "Spectate game",
      cls:
        "rounded-md border border-slate-300 dark:border-slate-700 text-slate-600 dark:text-slate-400 hover:border-slate-500 dark:hover:border-slate-500 hover:text-slate-800 dark:hover:text-slate-200 text-sm px-2 py-1 transition-colors"
    }
  }

  @impl true
  def update(%{entry: :all, identity: identity, aliases: aliases} = assigns, socket) do
    {open, running, completed, unavailable} = extract(:all, identity, aliases)

    {:ok,
     assign(socket, %{
       identity: identity,
       aliases: aliases,
       open: open,
       running: running,
       completed: completed,
       unavailable: unavailable,
       tab: Map.get(assigns, :tab, Map.get(socket.assigns, :tab, :running))
     })}
  end

  def update(_assigns, socket),
    do:
      {:ok,
       assign(socket, %{
         identity: nil,
         aliases: [],
         open: [],
         running: [],
         completed: [],
         unavailable: [],
         tab: :running
       })}

  @impl true
  def handle_event("challenges-tab", %{"value" => tab}, socket)
      when tab in ["open", "running", "completed", "unavailable"] do
    {:noreply, assign(socket, tab: String.to_atom(tab))}
  end

  def handle_event("challenges-tab", _, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div id="challenges-explore-wrap" class="content-wrap">
      <div class="flex flex-col gap-4">
        <div class="flex items-center justify-between">
          <h1 class="text-lg font-semibold text-slate-800 dark:text-slate-100">Challenge Explorer</h1>
        </div>

        <div class="inline-flex rounded-lg border border-slate-200 dark:border-slate-700 p-0.5 bg-slate-50 dark:bg-slate-800/40 w-fit">
          <button
            type="button"
            phx-click="challenges-tab"
            phx-target={@myself}
            value="running"
            class={tab_cls(@tab == :running)}
          ><span title="Running games" aria-label="Running games">▣</span></button>
          <button
            type="button"
            phx-click="challenges-tab"
            phx-target={@myself}
            value="open"
            class={tab_cls(@tab == :open)}
          ><span title="Open challenges" aria-label="Open challenges">▢</span></button>
          <button
            type="button"
            phx-click="challenges-tab"
            phx-target={@myself}
            value="completed"
            class={tab_cls(@tab == :completed)}
          ><span title="Completed games" aria-label="Completed games">◆</span></button>
          <button
            type="button"
            phx-click="challenges-tab"
            phx-target={@myself}
            value="unavailable"
            class={tab_cls(@tab == :unavailable)}
          ><span title="Blocked family" aria-label="Blocked family">⊘</span></button>
        </div>

        <%= case @tab do %>
          <% :open -> %>
            <%= if @open == [] do %>
              <p class="text-slate-400 dark:text-slate-600 text-sm">No open challenges.</p>
            <% else %>
              <div class="flex flex-col gap-2">
                <%= for game <- @open do %>
                  <div class="rounded-lg border border-slate-200 dark:border-slate-700 p-3 hover:border-amber-500 dark:hover:border-amber-400 transition-colors">
                    {game}
                  </div>
                <% end %>
              </div>
            <% end %>
          <% :running -> %>
            <%= if @running == [] do %>
              <p class="text-slate-400 dark:text-slate-600 text-sm">No running games.</p>
            <% else %>
              <div class="flex flex-col gap-2">
                <%= for game <- @running do %>
                  <div class="rounded-lg border border-slate-200 dark:border-slate-700 p-3 hover:border-amber-500 dark:hover:border-amber-400 transition-colors">
                    {game}
                  </div>
                <% end %>
              </div>
            <% end %>
          <% :completed -> %>
            <%= if @completed == [] do %>
              <p class="text-slate-400 dark:text-slate-600 text-sm">No completed games.</p>
            <% else %>
              <div class="flex flex-col gap-2">
                <%= for game <- @completed do %>
                  <div class="rounded-lg border border-slate-200 dark:border-slate-700 p-3 hover:border-amber-500 dark:hover:border-amber-400 transition-colors">
                    {game}
                  </div>
                <% end %>
              </div>
            <% end %>
          <% :unavailable -> %>
            <%= if @unavailable == [] do %>
              <p class="text-slate-400 dark:text-slate-600 text-sm">No blocked families.</p>
            <% else %>
              <div class="flex flex-col gap-2">
                <%= for game <- @unavailable do %>
                  <div class="rounded-lg border border-slate-200 dark:border-slate-700 p-3 opacity-60">
                    {game}
                  </div>
                <% end %>
              </div>
            <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp tab_cls(true),
    do:
      "rounded-md bg-amber-500 hover:bg-amber-400 text-white text-sm font-semibold px-3 py-1 transition-colors"

  defp tab_cls(false),
    do:
      "rounded-md text-slate-500 dark:text-slate-400 hover:text-slate-700 dark:hover:text-slate-200 text-sm font-semibold px-3 py-1 transition-colors"

  defp extract(:all, identity, aliases) do
    clump_id = Catenary.Preferences.get(:clump_id)

    case :ets.lookup(:challenges, :display) do
      [{_, games}] ->
        all = Enum.reject(games, &family_blocked?(&1, clump_id))
        blocked = Enum.filter(games, &family_blocked?(&1, clump_id))

        {
          Enum.map(open_games(all), &card(&1, identity, aliases)),
          Enum.map(running_games(all), &card(&1, identity, aliases)),
          Enum.map(completed_games(all), &card(&1, identity, aliases)),
          Enum.map(blocked, &card(&1, identity, aliases, actions: false))
        }

      [] ->
        {[], [], [], []}
    end
  end

  defp family_blocked?(game, clump_id) do
    case Map.get(game, :family) do
      tag when is_integer(tag) and tag >= 1 and tag <= 255 ->
        Catenary.BlockLog.blocked_family?(tag, clump_id)

      _ ->
        false
    end
  end

  # Open: awaiting an accepter and not withdrawn.
  defp open_games(games),
    do: Enum.filter(games, &(Map.get(&1, :accepter) == nil and Map.get(&1, :withdrawn) != true))

  # Running: an accepter has joined.
  defp running_games(games),
    do: Enum.filter(games, &(Map.get(&1, :accepter) != nil and Map.get(&1, :winner) == nil))

  # Completed: a winner has been decided.
  defp completed_games(games), do: Enum.filter(games, &(Map.get(&1, :winner) != nil))

  defp card(game, identity, aliases, opts \\ []) do
    badge = to_raw(status_badge(game, aliases))
    family = to_raw(family_badge(Map.get(game, :family)))
    id = short_id(Map.get(game, :game_id))
    challenger = to_raw(linked_author(Map.get(game, :challenger), aliases))
    accepter = to_raw(player(Map.get(game, :accepter), Map.get(game, :to), aliases))
    c_avatar = to_raw(Display.scaled_avatar(Map.get(game, :challenger), 2))
    a_id = Map.get(game, :accepter) || Map.get(game, :to)
    a_avatar = to_raw(if a_id, do: Display.scaled_avatar(a_id, 2), else: {:safe, ""})

    actions =
      if Keyword.get(opts, :actions, true) do
        actions(game, identity) |> Enum.map_join(&to_raw/1)
      else
        ""
      end

    {:safe,
     "<div class=\"flex items-center justify-between gap-2\">" <>
       "<div class=\"flex flex-col gap-1 min-w-0\">" <>
       "<div class=\"flex items-center gap-2\">" <>
       badge <>
       family <>
       "<span class=\"text-sm font-mono truncate\">" <>
       id <>
       "</span></div>" <>
       "<div class=\"text-xs text-slate-500 dark:text-slate-400 truncate flex items-center gap-1\">" <>
       c_avatar <>
       " " <>
       challenger <>
       " <span class=\"mx-0.5\">vs</span> " <>
       a_avatar <>
       " " <>
       accepter <>
       "</div></div>" <>
       "<div class=\"flex items-center gap-2 shrink-0\">" <> actions <> "</div></div>"}
  end

  defp family_badge(tag) when is_integer(tag) do
    name = QuaggaDef.family_name(tag)

    label =
      if name == :unknown, do: "family #{tag}", else: Atom.to_string(name)

    {:safe,
     "<span class=\"px-1.5 py-0.5 rounded text-[10px] font-bold uppercase bg-purple-500 text-white\">" <>
       label <> "</span>"}
  end

  defp family_badge(_), do: {:safe, ""}

  defp actions(game, identity) do
    []
    |> maybe_accept(game, identity)
    |> maybe_withdraw(game, identity)
    |> maybe_game_actions(game, identity)
  end

  # Accept is shown only for a pending game that is open to the viewer: not
  # the viewer's own challenge, and either open (to: nil) or addressed to them.
  # `accepter` may be absent (freshly-indexed games), hence Map.get.
  defp maybe_accept(list, game, identity) when is_binary(identity) do
    if Map.get(game, :accepter) == nil and Map.get(game, :challenger) != identity and
         Map.get(game, :withdrawn) != true and
         (is_nil(Map.get(game, :to)) or Map.get(game, :to) == identity) do
      list ++
        [
          {:safe,
           ~s(<button type="button" phx-click="accept-challenge" value=") <>
             game.game_id <>
             ~s(" phx-value-family=") <>
             Integer.to_string(game.family) <>
             ~s(" phx-value-challenger=") <>
             game.challenger <>
             ~s(" phx-value-challenge-commit=") <>
             to_string(Map.get(game, :challenge_commit) || "") <>
             ~s(" phx-disable-with="𝄇" title="Accept challenge" aria-label="Accept challenge" class="rounded-md bg-amber-500 hover:bg-amber-400 active:bg-amber-600 dark:bg-amber-400 dark:hover:bg-amber-300 dark:active:bg-amber-500 text-white dark:text-slate-900 text-sm font-semibold px-2 py-1 shadow-sm transition-colors">⚔</button>)}
        ]
    else
      list
    end
  end

  defp maybe_accept(list, _, _), do: list

  # Withdraw is shown only for the viewer's own still-pending challenge.
  defp maybe_withdraw(list, game, identity) when is_binary(identity) do
    if Map.get(game, :accepter) == nil and game.challenger == identity and
         game.withdrawn != true do
      list ++
        [
          {:safe,
           ~s(<button type="button" phx-click="withdraw-challenge" value=") <>
             game.game_id <>
             ~s(" phx-disable-with="𝄇" title="Withdraw challenge" aria-label="Withdraw challenge" class="rounded-md border border-amber-500 text-amber-600 dark:text-amber-400 hover:bg-amber-500 hover:text-white dark:hover:bg-amber-400 dark:hover:text-slate-900 text-sm font-semibold px-2 py-1 transition-colors">⤼</button>)}
        ]
    else
      list
    end
  end

  defp maybe_withdraw(list, _, _), do: list

  # Actions for accepted (live) games, decided by the viewer's involvement and
  # whose turn it is. All three open the game in BackgammonView; they differ in how
  # the move interface is presented there.
  #
  #   ▶  it is the viewer's game and their turn   (active move)
  #   ⏱  it is the viewer's game, opponent's turn (awaiting)
  #   ⌖  a game between other players             (spectate)
  defp maybe_game_actions(list, game, identity) when is_binary(identity) do
    cond do
      Map.get(game, :winner) != nil ->
        a = @game_actions.spectate

        list ++
          [
            {:safe,
             ~s(<button type="button" phx-click="play-game" value=") <>
               game.game_id <>
               ~s(" title=") <>
               a.title <>
               ~s(" aria-label=") <>
               a.title <> ~s(" class=") <> a.cls <> ~s(">) <> a.glyph <> ~s(</button>)}
          ]

      Map.get(game, :accepter) != nil ->
        running_actions(list, game, identity)

      true ->
        list
    end
  end

  defp maybe_game_actions(list, _, _), do: list

  defp running_actions(list, game, identity) do
    involved =
      identity in [game.challenger, Map.get(game, :accepter)]

    mover = Map.get(game, :mover)
    my_turn = involved and is_binary(mover) and mover == identity
    title = game_action_title(involved, my_turn)
    aria = if involved and my_turn, do: "Play your move", else: title

    # Navigating into a game writes no log, so these buttons carry no
    # phx-disable-with busy glyph and use neutral (non-amber) colors.
    list ++
      [
        {:safe,
         ~s(<button type="button" phx-click="play-game" value=") <>
           game.game_id <>
           ~s(" title=") <>
           title <>
           ~s(" aria-label=") <>
           aria <>
           ~s(" class=") <>
           game_action_cls(involved, my_turn) <>
           ~s(">) <>
           game_action_glyph(involved, my_turn) <>
           ~s(</button>)}
      ]
  end

  defp game_action(true, true), do: @game_actions.play
  defp game_action(true, false), do: @game_actions.await
  defp game_action(false, _), do: @game_actions.spectate

  defp game_action_glyph(involved, my_turn), do: game_action(involved, my_turn).glyph
  defp game_action_title(involved, my_turn), do: game_action(involved, my_turn).title
  defp game_action_cls(involved, my_turn), do: game_action(involved, my_turn).cls

  # Pending, aimed at a specific player (invited). `accepter` may be absent on
  # freshly-indexed games, so match on Map.get rather than the key itself.
  defp status_badge(%{winner: %{stake: stake, player: player}} = _game, aliases) do
    winner_avatar = to_raw(Display.scaled_avatar(player, 2))
    winner_name = to_raw(linked_author(player, aliases))

    {:safe,
     "<span class=\"px-1.5 py-0.5 rounded text-[10px] font-bold uppercase bg-slate-400 dark:bg-slate-500 text-white inline-flex items-center gap-1\">" <>
       "won (#{stake}x) " <>
       winner_avatar <>
       winner_name <>
       "</span>"}
  end

  defp status_badge(game, _aliases) do
    if Map.get(game, :accepter) == nil do
      pending_badge(Map.get(game, :to))
    else
      {:safe,
       "<span class=\"px-1.5 py-0.5 rounded text-[10px] font-bold uppercase bg-sky-500 text-white\">live</span>"}
    end
  end

  defp pending_badge(to) when is_binary(to),
    do:
      {:safe,
       "<span class=\"px-1.5 py-0.5 rounded text-[10px] font-bold uppercase bg-amber-500 text-white\">invited</span>"}

  defp pending_badge(_),
    do:
      {:safe,
       "<span class=\"px-1.5 py-0.5 rounded text-[10px] font-bold uppercase bg-emerald-500 text-white\">open</span>"}

  defp to_raw({:safe, html}), do: html

  # When the accepter is nil and `to` is set, show who the challenge is for.
  defp player(nil, to, aliases) when is_binary(to), do: linked_author(to, aliases)
  defp player(nil, _, _), do: {:safe, "<span class=\"italic text-slate-400\">waiting…</span>"}
  defp player(pk, _, aliases), do: linked_author(pk, aliases)

  defp linked_author(pk, aliases) do
    {:safe, html} = Display.linked_author(pk, aliases)
    {:safe, html}
  end

  # Display form of the game ID (Base62, full) — shared with EntryViewer.
  defp short_id(hex), do: Display.pretty_game_id(hex)
end
