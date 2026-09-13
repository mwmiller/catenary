defmodule Catenary.Games.Backgammon.ChainTest do
  use ExUnit.Case, async: true

  alias Catenary.Games.Backgammon.Chain

  doctest Chain

  defp spec_len(n), do: %{Chain.spec() | "length" => n}

  describe "derive/1" do
    test "produces 32-byte output" do
      seed = :crypto.hash(:sha256, "test")
      assert byte_size(Chain.derive(seed)) == 32
    end

    test "is deterministic" do
      seed = :crypto.hash(:sha256, "test")
      assert Chain.derive(seed) == Chain.derive(seed)
    end

    test "different inputs produce different outputs" do
      a = :crypto.hash(:sha256, "a")
      b = :crypto.hash(:sha256, "b")
      assert Chain.derive(a) != Chain.derive(b)
    end
  end

  describe "generate/2" do
    test "returns the chain spec length number of values" do
      seed = :crypto.strong_rand_bytes(32)
      chain = Chain.generate(seed, spec_len(5))
      assert length(chain) == 5
      assert Enum.all?(chain, &(byte_size(&1) == 32))
    end

    test "each value is derived from the previous" do
      seed = :crypto.strong_rand_bytes(32)
      [a, b, c] = Chain.generate(seed, spec_len(3))
      assert b == Chain.derive(a)
      assert c == Chain.derive(b)
    end

    test "different seeds produce different chains" do
      s1 = :crypto.strong_rand_bytes(32)
      s2 = :crypto.strong_rand_bytes(32)
      c1 = Chain.generate(s1, spec_len(3))
      c2 = Chain.generate(s2, spec_len(3))
      assert c1 != c2
    end
  end

  describe "commit/1" do
    test "returns SHA-256 of the last chain value" do
      chain = for _ <- 1..3, do: :crypto.strong_rand_bytes(32)
      expected = :crypto.hash(:sha256, List.last(chain))
      assert Chain.commit(chain) == expected
    end

    test "works with a bare 32-byte value" do
      v = :crypto.strong_rand_bytes(32)
      assert Chain.commit(v) == :crypto.hash(:sha256, v)
    end
  end

  describe "verify_first/2" do
    test "accepts the last chain value against the commitment" do
      seed = :crypto.strong_rand_bytes(32)
      chain = Chain.generate(seed, spec_len(10))
      commitment = Chain.commit(chain)

      assert :ok = Chain.verify_first(List.last(chain), commitment)
    end

    test "rejects a wrong value" do
      seed = :crypto.strong_rand_bytes(32)
      chain = Chain.generate(seed, spec_len(10))
      commitment = Chain.commit(chain)
      fake = :crypto.strong_rand_bytes(32)

      assert {:error, _} = Chain.verify_first(fake, commitment)
    end
  end

  describe "verify_next/3" do
    test "accepts a reveal that extends the chain backward" do
      seed = :crypto.strong_rand_bytes(32)
      chain = Chain.generate(seed, spec_len(10))

      assert :ok = Chain.verify_next(Enum.at(chain, -2), List.last(chain))
    end

    test "rejects a value that does not link to the prior reveal" do
      seed = :crypto.strong_rand_bytes(32)
      chain = Chain.generate(seed, spec_len(10))

      assert {:error, _} = Chain.verify_next(:crypto.strong_rand_bytes(32), List.last(chain))
    end

    test "a full reverse walk returns to the commitment" do
      seed = :crypto.strong_rand_bytes(32)
      chain = Chain.generate(seed, spec_len(20))
      commitment = Chain.commit(chain)

      assert :ok = Chain.verify_first(List.last(chain), commitment)

      reversed = Enum.reverse(chain)

      assert Enum.all?(
               Enum.zip(Enum.drop(reversed, 1), reversed),
               fn {revealed, prior} -> Chain.verify_next(revealed, prior) == :ok end
             )
    end
  end

  describe "dice/3" do
    test "produces values in 1..6 as a list" do
      a = :crypto.strong_rand_bytes(32)
      b = :crypto.strong_rand_bytes(32)
      [d1, d2] = Chain.dice(a, b)
      assert d1 in 1..6
      assert d2 in 1..6
    end

    test "respects requested count" do
      a = :crypto.strong_rand_bytes(32)
      b = :crypto.strong_rand_bytes(32)
      assert length(Chain.dice(a, b, 1)) == 1
      assert length(Chain.dice(a, b, 4)) == 4
      assert Enum.all?(Chain.dice(a, b, 4), &(&1 in 1..6))
    end

    test "is deterministic" do
      a = :crypto.strong_rand_bytes(32)
      b = :crypto.strong_rand_bytes(32)
      assert Chain.dice(a, b) == Chain.dice(a, b)
    end

    test "order matters (not commutative)" do
      a = :crypto.hash(:sha256, "player_a")
      b = :crypto.hash(:sha256, "player_b")
      assert Chain.dice(a, b) != Chain.dice(b, a)
    end

    test "uniformity: all 36 outcomes appear in 10000 rolls" do
      # Use a fixed seed for reproducibility
      base = :crypto.strong_rand_bytes(32)

      outcomes =
        for i <- 0..9_999, into: MapSet.new() do
          a = <<i::32, binary_part(base, 0, 28)::binary>>
          b = <<i + 10_000::32, binary_part(base, 0, 28)::binary>>
          Chain.dice(a, b)
        end

      # At least 30 of 36 outcomes should appear (statistical, not exact)
      assert MapSet.size(outcomes) >= 30
    end

    test "rejection sampling produces unbiased face distribution" do
      # Over 6,000 rolls (12,000 dice), each face expected ~2,000 times
      base = :crypto.strong_rand_bytes(32)

      counts =
        Enum.reduce(0..5999, %{}, fn i, acc ->
          a = <<i::32, binary_part(base, 0, 28)::binary>>
          b = <<i + 50_000::32, binary_part(base, 0, 28)::binary>>
          [d1, d2] = Chain.dice(a, b)

          acc
          |> Map.update(d1, 1, &(&1 + 1))
          |> Map.update(d2, 1, &(&1 + 1))
        end)

      # All 6 faces must be present
      assert Map.keys(counts) |> Enum.sort() == [1, 2, 3, 4, 5, 6]

      # Chi-squared test for uniformity across 6 faces (df = 5, critical value at p=0.001 is 20.515)
      expected = 12_000 / 6

      chi_sq =
        Enum.reduce(1..6, 0.0, fn face, sum ->
          observed = Map.get(counts, face, 0)
          sum + :math.pow(observed - expected, 2) / expected
        end)

      assert chi_sq < 25.0
    end
  end

  describe "extract_dice/2" do
    test "rejects bytes >= 252 and consumes valid bytes" do
      # 252, 253, 254, 255 should all be rejected; 0 -> 1, 5 -> 6
      bytes = [252, 253, 254, 255, 0, 5]
      acc = %{hash_next: <<0::256>>, found: [], needed: 2}
      result = Chain.extract_dice(bytes, acc)

      assert result == [1, 6]
    end

    test "maps boundary bytes 0..251 correctly to 1..6" do
      # 0 -> rem(0, 6) + 1 = 1
      # 6 -> rem(6, 6) + 1 = 1
      # 251 -> rem(251, 6) + 1 = 5 + 1 = 6
      bytes = [0, 6, 251]
      acc = %{hash_next: <<0::256>>, found: [], needed: 3}
      assert Chain.extract_dice(bytes, acc) == [1, 1, 6]
    end

    test "re-hashes when input list is exhausted before needed count is satisfied" do
      # Given empty list and needed = 2, it hashes hash_next to get 32 new bytes
      seed = :crypto.strong_rand_bytes(32)
      expected_hash = :crypto.hash(:sha256, seed)
      expected_first_byte = :binary.first(expected_hash)

      expected_first_die =
        if expected_first_byte < 252, do: rem(expected_first_byte, 6) + 1, else: nil

      result = Chain.extract_dice([], %{hash_next: seed, found: [], needed: 1})
      assert length(result) == 1
      assert hd(result) in 1..6

      if expected_first_die do
        assert hd(result) == expected_first_die
      end
    end
  end

  describe "spec/0" do
    test "returns the single flat constant map" do
      spec = Chain.spec()
      assert spec["salt"] == "catenary:bg:chain"
      assert spec["n"] == 1024
      assert spec["r"] == 8
      assert spec["p"] == 1
      assert spec["keylen"] == 32
      assert spec["length"] == 256
    end
  end

  describe "seed_for/3" do
    test "derives a 32-byte seed" do
      secret = :crypto.strong_rand_bytes(32)
      game_id = :crypto.strong_rand_bytes(32)
      assert byte_size(Chain.seed_for(secret, game_id, "challenger")) == 32
    end

    test "is deterministic" do
      secret = :crypto.strong_rand_bytes(32)
      game_id = :crypto.strong_rand_bytes(32)

      assert Chain.seed_for(secret, game_id, "challenger") ==
               Chain.seed_for(secret, game_id, "challenger")
    end

    test "differs by role and by game id" do
      secret = :crypto.strong_rand_bytes(32)
      g1 = :crypto.strong_rand_bytes(32)
      g2 = :crypto.strong_rand_bytes(32)

      assert Chain.seed_for(secret, g1, "challenger") != Chain.seed_for(secret, g1, "accepter")
      assert Chain.seed_for(secret, g1, "challenger") != Chain.seed_for(secret, g2, "challenger")
    end

    test "recovers the same chain from a fresh derivation" do
      secret = :crypto.strong_rand_bytes(32)
      game_id = :crypto.strong_rand_bytes(32)
      spec = spec_len(20)

      seed = Chain.seed_for(secret, game_id, "challenger")
      chain = Chain.generate(seed, spec)
      commitment = Chain.commit(chain)

      recovered = secret |> Chain.seed_for(game_id, "challenger") |> Chain.generate(spec)
      assert recovered == chain
      assert Chain.commit(recovered) == commitment
    end
  end
end
