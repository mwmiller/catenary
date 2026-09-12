defmodule Catenary.Backgammon.FoldTest do
  use ExUnit.Case, async: true

  alias Catenary.Backgammon.{Chain, Engine, Fold, Game, Notation}

  defp entry(map) do
    %Baobab.Entry{author: "a", log_id: 1, seqnum: 1, payload: CBOR.encode(map)}
  end

  defp hex(bin), do: Base.encode16(bin, case: :lower)
  defp short_spec, do: %{Chain.spec() | "length" => 8}

  # The next two fresh reveals for a player with `remaining` untouched chain
  # values — the exact indexing the runtime uses, so the fixtures and the fold
  # agree on where reveals come from without hand-counting chain offsets.
  defp next_reveals(chain, remaining), do: Chain.reveal_pair(chain, remaining)

  defp new_turn(player, turn, reveals, r_cur, r_next, moves, opp_half) do
    [d1, d2] = Chain.dice(r_cur, opp_half)
    roll = Game.roll_string(d1, d2)

    %{
      "type" => "turn",
      "game_id" => :crypto.strong_rand_bytes(32),
      "player" => player,
      "turn" => turn,
      "roll" => roll,
      "moves" => Notation.turn(moves),
      "r_cur" => hex(r_cur),
      "r_next" => hex(r_next),
      "reveals" => reveals
    }
  end

  defp new_roll(player, round, reveals, r_cur, r_next) do
    %{
      "type" => "roll",
      "game_id" => :crypto.strong_rand_bytes(32),
      "player" => player,
      "round" => round,
      "reveals" => reveals,
      "r_cur" => hex(r_cur),
      "r_next" => hex(r_next)
    }
  end

  # A two-turn game that opens with a mandatory roll round the challenger wins,
  # so the challenger is decided starter. Both chains are real generated chains
  # (short spec, so reveals are shared across the opening and both turns).
  defp two_turn_game do
    len = short_spec()["length"]

    {chall, accept} =
      Enum.reduce_while(Stream.repeatedly(fn -> 0 end), nil, fn _, _ ->
        chall = Chain.generate(:crypto.strong_rand_bytes(32), short_spec())
        accept = Chain.generate(:crypto.strong_rand_bytes(32), short_spec())

        # Single-die rolls: challenger mixes with the accepter's
        # accept-reveal (known at accept), accepter with the challenger's
        # just-announced next reveal. The challenger must win round 0.
        {c0, c0_next} = next_reveals(chall, len)
        {a0, _} = next_reveals(accept, len - 1)

        dc = Chain.dice(c0, List.last(accept), 1) |> hd()
        da = Chain.dice(a0, c0_next, 1) |> hd()

        if dc > da, do: {:halt, {chall, accept}}, else: {:cont, nil}
      end)

    accept_reveal = List.last(accept)

    pk_challenger = "pk-challenger"
    pk_accepter = "pk-accepter"

    game = %{
      challenger: pk_challenger,
      accepter: pk_accepter,
      family: 1,
      game_id: Base.encode16(:crypto.strong_rand_bytes(32), case: :lower),
      challenge_commit: hex(Chain.commit(chall)),
      accept_commit: hex(Chain.commit(accept))
    }

    play_map = %{
      "type" => "play",
      "game_id" => :crypto.strong_rand_bytes(32),
      "player" => pk_accepter,
      "reveal" => hex(accept_reveal)
    }

    {c0_cur, c0_next} = next_reveals(chall, len)
    {a0_cur, a0_next} = next_reveals(accept, len - 1)
    d_c = Chain.dice(c0_cur, accept_reveal, 1) |> hd()
    d_a = Chain.dice(a0_cur, c0_next, 1) |> hd()
    true = d_c > d_a

    r0c = new_roll(pk_challenger, 0, len, c0_cur, c0_next)
    r0a = new_roll(pk_accepter, 0, len - 1, a0_cur, a0_next)

    # The challenger, decided starter, plays turn 1. The opponent half is the
    # half the accepter ALREADY announced as r0a's r_next; the fold hands it
    # back as opp_for_next. The accepter answers at turn 2 with the
    # challenger's turn-1 r_next as its opponent half.
    {c1_cur, c1_next} = next_reveals(chall, len - 2)
    {a2_cur, a2_next} = next_reveals(accept, len - 3)

    # Turn 1 uses the opener dice (d_c, d_a), not Chain.dice for this turn.
    play1 = Engine.legal_plays(Engine.initial(), {d_c, d_a}) |> hd()
    pos2 = Engine.mirror(Engine.apply(Engine.initial(), play1))

    [d2a, d2b] = Chain.dice(a2_cur, c1_next)
    play2 = Engine.legal_plays(pos2, {d2a, d2b}) |> hd()

    # The roll string in the entry must match the opener dice.
    turn1_roll = Game.roll_string(d_c, d_a)
    turn1 = Map.put(new_turn(pk_challenger, 1, len - 2, c1_cur, c1_next, play1, a0_next), "roll", turn1_roll)
    turn2 = new_turn(pk_accepter, 2, len - 3, a2_cur, a2_next, play2, c1_next)

    %{
      game: game,
      play_map: play_map,
      r0c: r0c,
      r0a: r0a,
      turn1: turn1,
      turn2: turn2,
      pos2: pos2,
      play1: play1,
      play2: play2
    }
  end

  describe "fold_game/2 — full game with turns" do
    test "folds a legal two-turn game into position, history, and mover" do
      f = two_turn_game()

      reader = fn pk, _, _ ->
        cond do
          pk == f.game.challenger -> [entry(f.r0c), entry(f.turn1)]
          pk == f.game.accepter -> [entry(f.play_map), entry(f.r0a), entry(f.turn2)]
        end
      end

      result = Fold.fold_game(f.game, %{reader: reader, spec: short_spec()})

      assert result.error == :none
      assert result.turn_count == 2
      assert result.opener.starter == f.game.challenger
      assert result.opener.rounds == 1
      assert result.mover == f.game.challenger

      expected = Engine.mirror(Engine.apply(f.pos2, f.play2))
      assert result.position == expected

      assert [t1, t2] = result.history
      assert t1.turn == 1
      assert t1.player == f.game.challenger
      assert t1.moves == Notation.turn(f.play1)
      assert t1.after == Engine.apply(Engine.initial(), f.play1)
      assert length(t1.frames) == length(f.play1) + 1

      assert t2.turn == 2
      assert t2.player == f.game.accepter
      assert t2.after == Engine.apply(f.pos2, f.play2)
    end
  end

  describe "fold_game/2 — tamper detection" do
    test "rejects a roll that was tampered with after the fact" do
      f = two_turn_game()

      bad_turn1 = Map.update!(f.turn1, "roll", fn _ -> "6-6" end)

      reader = fn pk, _, _ ->
        cond do
          pk == f.game.challenger -> [entry(f.r0c), entry(bad_turn1)]
          pk == f.game.accepter -> [entry(f.play_map), entry(f.r0a)]
        end
      end

      result = Fold.fold_game(f.game, %{reader: reader, spec: short_spec()})

      assert result.error =~ "roll mismatch"
    end

    test "rejects a turn authored by the wrong player" do
      f = two_turn_game()

      wrong = Map.put(f.turn1, "player", "imposter")

      reader = fn pk, _, _ ->
        cond do
          pk == f.game.challenger -> [entry(f.r0c), entry(wrong)]
          pk == f.game.accepter -> [entry(f.play_map), entry(f.r0a), entry(f.turn2)]
        end
      end

      result = Fold.fold_game(f.game, %{reader: reader, spec: short_spec()})

      assert result.turn_count == 0
      assert result.error =~ "authored"
    end
  end

  describe "fold_game/2 — reveal counter" do
    test "rejects a reveal counter that does not step down from the chain max" do
      f = two_turn_game()

      wrong_count = Map.put(f.turn1, "reveals", f.turn1["reveals"] + 1)

      reader = fn pk, _, _ ->
        cond do
          pk == f.game.challenger -> [entry(f.r0c), entry(wrong_count)]
          pk == f.game.accepter -> [entry(f.play_map), entry(f.r0a), entry(f.turn2)]
        end
      end

      result = Fold.fold_game(f.game, %{reader: reader, spec: short_spec()})

      assert result.error =~ "reveal counter"
    end
  end

  describe "fold_game/2 — opening state" do
    test "an accepted game with no turns stays in the opening" do
      game = %{
        challenger: "pk-c",
        accepter: "pk-a",
        family: 1,
        game_id: Base.encode16(:crypto.strong_rand_bytes(32), case: :lower),
        challenge_commit: hex(:crypto.strong_rand_bytes(32)),
        accept_commit: hex(:crypto.strong_rand_bytes(32))
      }

      result = Fold.fold_game(game, %{reader: fn _, _, _ -> [] end})

      assert result.error == :none
      assert result.turn_count == 0
      assert result.opener == nil
      assert result.mover == "pk-c"
      assert result.position == Engine.initial()
    end
  end

  describe "fold_game/2 — opening rolls" do
    # Real chains whose first opening round rolls equal (a tie) and whose second
    # round favors the accepter, so the opening decides the accepter as starter.
    defp opening_game do
      len = short_spec()["length"]

      {c, a} =
        Enum.reduce_while(Stream.repeatedly(fn -> 0 end), nil, fn _, _ ->
          c = Chain.generate(:crypto.strong_rand_bytes(32), short_spec())
          a = Chain.generate(:crypto.strong_rand_bytes(32), short_spec())

          # Round dice are single-die rolls: each player mixes their reveal
          # with the opponent's most-recently-published half (the accepter's
          # accept-reveal for the challenger's first roll; r0a_next for the
          # challenger in round 1). Round 0 must tie, round 1 favor accepter.
          {c0, c0_next} = next_reveals(c, len)
          {a0, a0_next} = next_reveals(a, len - 1)
          {c1, c1_next} = next_reveals(c, len - 2)
          {a1, _} = next_reveals(a, len - 3)

          d_c0 = Chain.dice(c0, List.last(a), 1) |> hd()
          d_a0 = Chain.dice(a0, c0_next, 1) |> hd()
          d_c1 = Chain.dice(c1, a0_next, 1) |> hd()
          d_a1 = Chain.dice(a1, c1_next, 1) |> hd()

          if d_c0 == d_a0 and d_a1 > d_c1, do: {:halt, {c, a}}, else: {:cont, nil}
        end)

      game = %{
        challenger: "pk-c",
        accepter: "pk-a",
        family: 1,
        game_id: Base.encode16(:crypto.strong_rand_bytes(32), case: :lower),
        challenge_commit: hex(Chain.commit(c)),
        accept_commit: hex(Chain.commit(a))
      }

      play_map = %{
        "type" => "play",
        "game_id" => :crypto.strong_rand_bytes(32),
        "player" => "pk-a",
        "reveal" => hex(List.last(a))
      }

      # Round 0 ties; round 1 goes to the accepter. The accept reveal is only
      # the chain anchor (verified against the accept commitment); every r_cur
      # on a roll/turn entry is a FRESH chain value extending the prior, so the
      # accepter's entries spend a[-2]/a[-3], then a[-4]/a[-5], then a[-6]/a[-7].
      {r0c_cur, r0c_next} = next_reveals(c, len)
      {r0a_cur, r0a_next} = next_reveals(a, len - 1)
      {r1c_cur, r1c_next} = next_reveals(c, len - 2)
      {r1a_cur, r1a_next} = next_reveals(a, len - 3)

      r0c = new_roll("pk-c", 0, len, r0c_cur, r0c_next)
      r0a = new_roll("pk-a", 0, len - 1, r0a_cur, r0a_next)
      r1c = new_roll("pk-c", 1, len - 2, r1c_cur, r1c_next)
      r1a = new_roll("pk-a", 1, len - 3, r1a_cur, r1a_next)

      # Round dice single-die rolls (the fold mixes each player's reveal with
      # the opponent's most-recently-published half); this re-checks the tie +
      # accepter win selected above.
      d1 = Chain.dice(r0c_cur, List.last(a), 1) |> hd()
      d2 = Chain.dice(r0a_cur, r0c_next, 1) |> hd()
      d3 = Chain.dice(r1c_cur, r0a_next, 1) |> hd()
      d4 = Chain.dice(r1a_cur, r1c_next, 1) |> hd()
      true = d1 == d2 and d4 > d3

      # The accepter, as starter, plays turn 1. Their half is a fresh reveal;
      # the challenger's half for that roll is the one they ALREADY announced
      # as r1c's r_next — the fold hands it back as opp_for_next.
      {a6_cur, a6_next} = next_reveals(a, len - 5)

      # Turn 1 uses the opener dice (d3, d4), not Chain.dice for this turn.
      play1 = Engine.legal_plays(Engine.initial(), {d3, d4}) |> hd()

      turn1_roll = Game.roll_string(d3, d4)
      turn1 =
        Map.put(new_turn("pk-a", 1, len - 5, a6_cur, a6_next, play1, r1c_next), "roll", turn1_roll)

      {game, play_map, [r0c, r0a, r1c, r1a], turn1, c}
    end

    test "opening rolls pick the starter and anchor turn parity to them" do
      {game, play_map, [r0c, r0a, r1c, r1a], turn1, _c_chain} = opening_game()
      len = short_spec()["length"]

      challenger_rolls = [entry(r0c), entry(r1c)]
      accepter_rolls = [entry(r0a), entry(r1a)]

      reader = fn pk, _, _ ->
        cond do
          pk == game.challenger -> challenger_rolls
          pk == game.accepter -> [entry(play_map)] ++ accepter_rolls ++ [entry(turn1)]
        end
      end

      result = Fold.fold_game(game, %{reader: reader, spec: short_spec()})

      assert result.error == :none, "fold error: #{result.error}"
      assert result.opener.starter == game.accepter
      assert result.opener.rounds == 2

      # Tied round 0 then a round-1 win costs both players four reveals; the
      # starter then spends two more on turn 1.
      assert result.remaining[game.challenger] == len - 4
      assert result.remaining[game.accepter] == len - 7

      assert [t1] = result.history
      assert t1.turn == 1
      assert t1.player == game.accepter
      assert result.mover == game.challenger
    end

    test "an opening that has not resolved yet yields no starter and no turns" do
      {game, play_map, [r0c, _r0a, _r1c, _r1a], _turn1, _c_chain} = opening_game()

      # Only the challenger's first-round roll is in: the round is incomplete.
      reader = fn pk, _, _ ->
        cond do
          pk == game.challenger -> [entry(r0c)]
          pk == game.accepter -> [entry(play_map)]
        end
      end

      result = Fold.fold_game(game, %{reader: reader, spec: short_spec()})

      assert result.error == :none
      assert result.opener == nil
      assert result.turn_count == 0
      assert result.mover == game.accepter
    end
  end
end
