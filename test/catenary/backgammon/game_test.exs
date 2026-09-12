defmodule Catenary.Backgammon.GameTest do
  use ExUnit.Case, async: true

  alias Catenary.Backgammon.{Chain, Game}

  doctest Game

  @pk1 "3bwyzGHRCGFN7voPAbRSP7vnF4pRdBX4S66C9ZKE9d46eCj8"
  @pk2 "7DZBdggWM6Hs7gvdrgcznmMpPaKaND94p5GSCQWnzjcBxpDU"
  @game_id :crypto.strong_rand_bytes(32)

  describe "game_base/3" do
    test "produces a 56-bit integer" do
      gb = Game.game_base(@pk1, @pk2, @game_id)
      assert is_integer(gb)
      assert gb >= 0
      assert gb < Bitwise.bsl(1, 56)
    end

    test "is deterministic" do
      assert Game.game_base(@pk1, @pk2, @game_id) == Game.game_base(@pk1, @pk2, @game_id)
    end

    test "order of keys matters" do
      forward = Game.game_base(@pk1, @pk2, @game_id)
      reverse = Game.game_base(@pk2, @pk1, @game_id)
      assert forward != reverse
    end

    test "different game IDs produce different bases" do
      other_id = :crypto.strong_rand_bytes(32)
      assert Game.game_base(@pk1, @pk2, @game_id) != Game.game_base(@pk1, @pk2, other_id)
    end
  end

  describe "game_log_id/2" do
    test "base 0, facet 0 gives 0" do
      assert Game.game_log_id(0, 0) == 0
    end

    test "facet 1 shifts into the high byte" do
      assert Game.game_log_id(0, 1) == Bitwise.bsl(1, 56)
    end

    test "OR combines base and facet correctly" do
      base = 0xABCDEF
      facet = 0x42
      expected = Bitwise.bor(base, Bitwise.bsl(facet, 56))
      assert Game.game_log_id(base, facet) == expected
    end
  end

  describe "chain_spec/0" do
    test "matches the chain module spec" do
      assert Game.chain_spec() == Chain.spec()
    end
  end

  describe "challenge_entry/4" do
    test "returns correct structure" do
      commit = :crypto.strong_rand_bytes(32)
      entry = Game.challenge_entry(@pk1, @game_id, 1, commit)

      assert entry["type"] == "challenge"
      assert entry["player"] == @pk1
      assert entry["game_id"] == @game_id
      assert entry["family"] == 1
      assert entry["chain_spec"] == Game.chain_spec()
      assert entry["chain_commit"] == Base.encode16(commit, case: :lower)
      assert entry["to"] == nil
    end

    test "chain_commit is optional" do
      entry = Game.challenge_entry(@pk1, @game_id, 2)

      assert entry["family"] == 2
      assert entry["chain_commit"] == nil
      assert entry["chain_spec"] == Game.chain_spec()
      assert entry["to"] == nil
    end

    test "open challenge has no to field" do
      entry = Game.challenge_entry(@pk1, @game_id, 1, nil, nil, nil)
      refute Map.has_key?(entry, "to")
    end

    test "directed challenge includes the to field" do
      entry = Game.challenge_entry(@pk1, @game_id, 1, nil, nil, @pk2)
      assert entry["to"] == @pk2
    end
  end

  describe "accept_entry/4" do
    test "returns correct structure" do
      commit = :crypto.strong_rand_bytes(32)
      entry = Game.accept_entry(@pk2, @game_id, 1, commit)

      assert entry["type"] == "accept"
      assert entry["player"] == @pk2
      assert entry["game_id"] == @game_id
      assert entry["family"] == 1
      assert entry["chain_spec"] == Game.chain_spec()
      assert entry["chain_commit"] == Base.encode16(commit, case: :lower)
      assert entry["reveal"] == nil
    end

    test "chain_commit is optional" do
      entry = Game.accept_entry(@pk2, @game_id, 2)

      assert entry["family"] == 2
      assert entry["chain_commit"] == nil
    end

    test "accepts an opening reveal" do
      commit = :crypto.strong_rand_bytes(32)
      reveal = :crypto.strong_rand_bytes(32)
      entry = Game.accept_entry(@pk2, @game_id, 1, commit, Game.chain_spec(), reveal)

      assert entry["reveal"] == Base.encode16(reveal, case: :lower)
    end
  end

  describe "play_entry/5" do
    test "self-describing kickoff carries the full game context for reconstruction" do
      a_commit = :crypto.strong_rand_bytes(32)
      c_commit = :crypto.strong_rand_bytes(32)
      reveal = :crypto.strong_rand_bytes(32)
      base = Game.game_base(@pk1, @pk2, @game_id, 1)
      log_id = Game.game_log_id(base, 3)

      entry =
        Game.play_entry(@pk2, @game_id, 1, @pk1, base,
          game_log_id: log_id,
          chain_commit: a_commit,
          challenger_commit: c_commit,
          reveal: reveal,
          chain_spec: Game.chain_spec()
        )

      assert entry["type"] == "play"
      assert entry["game_id"] == @game_id
      assert entry["family"] == 1
      assert entry["player"] == @pk2
      assert entry["role"] == "accepter"
      assert entry["challenger"] == @pk1
      assert entry["chain_spec"] == Game.chain_spec()
      assert entry["chain_commit"] == Base.encode16(a_commit, case: :lower)
      assert entry["challenger_commit"] == Base.encode16(c_commit, case: :lower)
      assert entry["reveal"] == Base.encode16(reveal, case: :lower)
      assert entry["game_base"] == base
      assert entry["game_log_id"] == log_id
    end

    test "chain fields default to nil; base stays derivable from the participants" do
      base = Game.game_base(@pk1, @pk2, @game_id, 2)
      entry = Game.play_entry(@pk2, @game_id, 2, @pk1, base)

      assert entry["game_base"] == base
      assert entry["game_log_id"] == nil
      assert entry["chain_commit"] == nil
      assert entry["challenger_commit"] == nil
      assert entry["reveal"] == nil
      assert entry["chain_spec"] == Game.chain_spec()
    end
  end

  describe "full game flow integration" do
    test "challenge/accept carry the spec; reverse reveals verify back to the commitment" do
      secret1 = :crypto.strong_rand_bytes(32)
      secret2 = :crypto.strong_rand_bytes(32)
      spec = %{Chain.spec() | "length" => 20}

      # Challenger sets up a recoverable chain
      c_seed = Chain.seed_for(secret1, @game_id, "challenger", spec)
      c_chain = Chain.generate(c_seed, spec)
      c_commit = Chain.commit(c_chain)

      # Accepter sets up a recoverable chain
      a_seed = Chain.seed_for(secret2, @game_id, "accepter", spec)
      a_chain = Chain.generate(a_seed, spec)
      a_commit = Chain.commit(a_chain)

      # Challenge + accept with the spec echoed
      challenge = Game.challenge_entry(@pk1, @game_id, 1, c_commit, spec)
      accept = Game.accept_entry(@pk2, @game_id, 1, a_commit, spec, List.last(a_chain))
      assert challenge["type"] == "challenge"
      assert accept["type"] == "accept"
      assert challenge["chain_spec"] == spec
      assert accept["chain_spec"] == spec

      # Accepter's opening reveal (chain[-1]) rides on the accept
      b1 = Base.decode16!(accept["reveal"], case: :lower)
      assert b1 == List.last(a_chain)
      assert :ok = Chain.verify_first(b1, a_commit)

      # Challenger's opening turn reveals its own last + next-to-last values
      a1 = List.last(c_chain)
      a2 = Enum.at(c_chain, -2)
      assert :ok = Chain.verify_first(a1, c_commit)
      assert :ok = Chain.verify_next(a2, a1)

      # Turn-1 dice come from the two freshly-revealed halves
      [d1, d2] = Chain.dice(a1, b1)
      assert d1 in 1..6 and d2 in 1..6

      # A seed-forged recovery reproduces the challenger's committed chain
      recovered =
        secret1
        |> Chain.seed_for(@game_id, "challenger", spec)
        |> Chain.generate(spec)

      assert Chain.commit(recovered) == c_commit

      # Game base and log IDs are stable
      gb = Game.game_base(@pk1, @pk2, @game_id)
      assert Game.game_log_id(gb, 0) == gb
      assert Game.game_log_id(gb, 1) == Bitwise.bor(gb, Bitwise.bsl(1, 56))
    end
  end
end
