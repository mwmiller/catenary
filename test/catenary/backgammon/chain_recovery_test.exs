defmodule Catenary.Backgammon.ChainRecoveryTest do
  @moduledoc """
  End-to-end test for chain re-derivation on a fresh device.

  Verifies that a device with only the identity secret and log entries
  can reconstruct the full chain and verify all reveals without any
  local state.
  """
  use ExUnit.Case, async: true

  alias Catenary.Backgammon.{Chain, Engine, Fold, Game, Notation}

  defp hex(bin), do: Base.encode16(bin, case: :lower)

  defp short_spec, do: %{Chain.spec() | "length" => 8}

  # Generate a chain from a known identity secret (simulates fresh device)
  defp chain_from_secret(secret, game_id, role, spec) do
    seed = Chain.seed_for(secret, game_id, role, spec)
    Chain.generate(seed, spec)
  end

  describe "chain re-derivation from identity secret" do
    test "re-derives chain from secret and verifies commitment" do
      spec = short_spec()
      secret = :crypto.strong_rand_bytes(32)
      game_id = :crypto.strong_rand_bytes(32)

      # Original chain generation (simulates the player's device)
      original_chain = chain_from_secret(secret, game_id, "challenger", spec)
      commitment = Chain.commit(original_chain)

      # Fresh device re-derives the chain from the same inputs
      recovered_chain = chain_from_secret(secret, game_id, "challenger", spec)

      # Chains must match exactly
      assert original_chain == recovered_chain

      # Commitment must match
      assert Chain.commit(recovered_chain) == commitment
    end

    test "different roles produce different chains" do
      spec = short_spec()
      secret = :crypto.strong_rand_bytes(32)
      game_id = :crypto.strong_rand_bytes(32)

      challenger_chain = chain_from_secret(secret, game_id, "challenger", spec)
      accepter_chain = chain_from_secret(secret, game_id, "accepter", spec)

      # Same secret, different roles → different chains
      assert challenger_chain != accepter_chain
    end

    test "different game IDs produce different chains" do
      spec = short_spec()
      secret = :crypto.strong_rand_bytes(32)
      game_id_1 = :crypto.strong_rand_bytes(32)
      game_id_2 = :crypto.strong_rand_bytes(32)

      chain_1 = chain_from_secret(secret, game_id_1, "challenger", spec)
      chain_2 = chain_from_secret(secret, game_id_2, "challenger", spec)

      assert chain_1 != chain_2
    end

    test "reveal verification against re-derived chain" do
      spec = short_spec()
      secret = :crypto.strong_rand_bytes(32)
      game_id = :crypto.strong_rand_bytes(32)

      chain = chain_from_secret(secret, game_id, "challenger", spec)
      commitment = Chain.commit(chain)

      # Take reveals from the end of the chain (as published)
      len = spec["length"]
      {r1, r2} = Chain.reveal_pair(chain, len)

      # Fresh device verifies: first reveal matches commitment
      assert Chain.verify_first(r1, commitment) == :ok

      # Second reveal chains from first
      assert Chain.verify_next(r2, r1) == :ok
    end

    test "tampered reveal fails verification" do
      spec = short_spec()
      secret = :crypto.strong_rand_bytes(32)
      game_id = :crypto.strong_rand_bytes(32)

      chain = chain_from_secret(secret, game_id, "challenger", spec)
      commitment = Chain.commit(chain)

      len = spec["length"]
      {r1, _r2} = Chain.reveal_pair(chain, len)

      # Tamper with the reveal
      tampered = binary_part(r1, 0, 31) <> <<0>>

      # Verification fails
      assert {:error, _} = Chain.verify_first(tampered, commitment)
    end
  end

  describe "full game recovery from logs" do
    test "reconstructs game state from logs on fresh device" do
      spec = short_spec()

      # Generate identity secrets (simulating two players)
      challenger_secret = :crypto.strong_rand_bytes(32)
      accepter_secret = :crypto.strong_rand_bytes(32)

      game_id = :crypto.strong_rand_bytes(32)

      # Generate chains from secrets
      chall_chain = chain_from_secret(challenger_secret, game_id, "challenger", spec)
      accept_chain = chain_from_secret(accepter_secret, game_id, "accepter", spec)

      # Accept reveal (last element of accepter's chain)
      accept_reveal = List.last(accept_chain)

      # Opening rolls: challenger wins
      len = spec["length"]
      {c0_cur, c0_next} = Chain.reveal_pair(chall_chain, len)
      {a0_cur, a0_next} = Chain.reveal_pair(accept_chain, len - 1)

      d_c = Chain.dice(c0_cur, accept_reveal, 1) |> hd()
      d_a = Chain.dice(a0_cur, c0_next, 1) |> hd()

      # Ensure challenger wins opening (regenerate if needed)
      {chall_chain, accept_chain, c0_cur, c0_next, a0_cur, a0_next, accept_reveal} =
        if d_c > d_a do
          {chall_chain, accept_chain, c0_cur, c0_next, a0_cur, a0_next, accept_reveal}
        else
          # Regenerate with new secrets until challenger wins
          recalc_challenger_opens(spec, game_id)
        end

      # Build game metadata with correct commitments
      game = %{
        challenger: "pk-challenger",
        accepter: "pk-accepter",
        family: 1,
        game_id: hex(game_id),
        challenge_commit: hex(Chain.commit(chall_chain)),
        accept_commit: hex(Chain.commit(accept_chain))
      }

      # Build log entries
      r0c = %{
        "type" => "roll",
        "game_id" => game_id,
        "player" => "pk-challenger",
        "round" => 0,
        "reveals" => len,
        "r_cur" => hex(c0_cur),
        "r_next" => hex(c0_next)
      }

      r0a = %{
        "type" => "roll",
        "game_id" => game_id,
        "player" => "pk-accepter",
        "round" => 0,
        "reveals" => len - 1,
        "r_cur" => hex(a0_cur),
        "r_next" => hex(a0_next)
      }

      # Turn 1: challenger moves
      {c1_cur, c1_next} = Chain.reveal_pair(chall_chain, len - 2)
      [d1a, d1b] = Chain.dice(c1_cur, a0_next)
      play1 = Engine.legal_plays(Engine.initial(), {d1a, d1b}) |> hd()

      turn1 = %{
        "type" => "turn",
        "game_id" => game_id,
        "player" => "pk-challenger",
        "turn" => 1,
        "roll" => Game.roll_string(d1a, d1b),
        "moves" => Notation.turn(play1),
        "r_cur" => hex(c1_cur),
        "r_next" => hex(c1_next),
        "reveals" => len - 2
      }

      # Turn 2: accepter moves
      {a2_cur, a2_next} = Chain.reveal_pair(accept_chain, len - 3)
      pos2 = Engine.mirror(Engine.apply(Engine.initial(), play1))
      [d2a, d2b] = Chain.dice(a2_cur, c1_next)
      play2 = Engine.legal_plays(pos2, {d2a, d2b}) |> hd()

      turn2 = %{
        "type" => "turn",
        "game_id" => game_id,
        "player" => "pk-accepter",
        "turn" => 2,
        "roll" => Game.roll_string(d2a, d2b),
        "moves" => Notation.turn(play2),
        "r_cur" => hex(a2_cur),
        "r_next" => hex(a2_next),
        "reveals" => len - 3
      }

      # Play entry (kickoff)
      play_entry = %{
        "type" => "play",
        "game_id" => game_id,
        "player" => "pk-accepter",
        "reveal" => hex(accept_reveal)
      }

      # Reader function (simulates reading from Baobab)
      reader = fn pk, _, _ ->
        cond do
          pk == game.challenger ->
            [
              %Baobab.Entry{author: pk, log_id: 1, seqnum: 1, payload: CBOR.encode(r0c)},
              %Baobab.Entry{author: pk, log_id: 1, seqnum: 2, payload: CBOR.encode(turn1)}
            ]

          pk == game.accepter ->
            [
              %Baobab.Entry{author: pk, log_id: 1, seqnum: 1, payload: CBOR.encode(play_entry)},
              %Baobab.Entry{author: pk, log_id: 1, seqnum: 2, payload: CBOR.encode(r0a)},
              %Baobab.Entry{author: pk, log_id: 1, seqnum: 3, payload: CBOR.encode(turn2)}
            ]
        end
      end

      # Fresh device folds the game from logs only
      result =
        Fold.fold_game(game, %{reader: reader, spec: spec, accept_reveal: hex(accept_reveal)})

      # Verify the game reconstructed correctly
      assert result.error == :none
      assert result.turn_count == 2
      assert result.opener.starter == game.challenger
      assert result.opener.rounds == 1
      assert result.mover == game.challenger

      # Verify position matches expected
      expected_pos = Engine.mirror(Engine.apply(pos2, play2))
      assert result.position == expected_pos

      # Verify history
      assert [h1, h2] = result.history
      assert h1.turn == 1
      assert h1.player == game.challenger
      assert h2.turn == 2
      assert h2.player == game.accepter
    end

    test "fresh device can verify dice from reveals" do
      spec = short_spec()
      secret = :crypto.strong_rand_bytes(32)
      game_id = :crypto.strong_rand_bytes(32)

      chain = chain_from_secret(secret, game_id, "challenger", spec)
      len = spec["length"]

      # Take a reveal pair
      {r_cur, _r_next} = Chain.reveal_pair(chain, len)

      # Fresh device computes dice from the reveals
      opp_half = :crypto.strong_rand_bytes(32)
      [d1, d2] = Chain.dice(r_cur, opp_half)

      # Dice are valid
      assert d1 in 1..6
      assert d2 in 1..6

      # Same inputs produce same dice (deterministic)
      [d1_again, d2_again] = Chain.dice(r_cur, opp_half)
      assert d1 == d1_again
      assert d2 == d2_again
    end
  end

  # Recalculate until challenger wins the opening
  defp recalc_challenger_opens(spec, game_id) do
    len = spec["length"]

    # Generate new secrets
    challenger_secret_new = :crypto.strong_rand_bytes(32)
    accepter_secret_new = :crypto.strong_rand_bytes(32)

    chall_chain = chain_from_secret(challenger_secret_new, game_id, "challenger", spec)
    accept_chain = chain_from_secret(accepter_secret_new, game_id, "accepter", spec)

    accept_reveal = List.last(accept_chain)

    {c0_cur, c0_next} = Chain.reveal_pair(chall_chain, len)
    {a0_cur, a0_next} = Chain.reveal_pair(accept_chain, len - 1)

    d_c = Chain.dice(c0_cur, accept_reveal, 1) |> hd()
    d_a = Chain.dice(a0_cur, c0_next, 1) |> hd()

    if d_c > d_a do
      {chall_chain, accept_chain, c0_cur, c0_next, a0_cur, a0_next, accept_reveal}
    else
      recalc_challenger_opens(spec, game_id)
    end
  end
end
