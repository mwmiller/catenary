defmodule Catenary.Backgammon.Chain do
  @moduledoc """
  Provably-fair scrypt chain for Catenary backgammon.

  Each player holds a deterministic chain of 32-byte values:

      chain[0]   = scrypt(seed, salt, n, r, p, keylen)
      chain[i+1] = scrypt(chain[i], salt, n, r, p, keylen)

  where the seed is derived from the player's identity secret so that the
  whole chain can be **recovered from the logs alone** (fresh device,
  lost local state):

      seed = scrypt(identity_secret, salt <> ":seed:" <> game_id <> ":" <> role, ...)

  The **commitment** is `SHA-256(chain[-1])` — the hash of the last value —
  published when the game begins so the player cannot change their chain
  after seeing the opponent's play.

  Reveals walk the chain **in reverse order**: the first reveal is the last
  element, `chain[-1]`, then `chain[-2]`, and so on. Because each value is a
  one-way preimage of the previous, publishing an early reveal never leaks
  the later ones, so neither player can look past the other's commitment.

  Reveals are verified incrementally:

      Chain.verify_first(revealed, commitment)   # SHA-256(revealed) == commitment
      Chain.verify_next(revealed, prior_reveal)  # derive(revealed) == prior_reveal

  The dice for a turn come from two freshly-revealed halves (one per player):

      dice = SHA-256(mover_half <> opponent_half)    # two values in 1..6

  ## Chain spec

  Every variable constant lives in a single flat map, the **chain spec**, so
  that a challenge message is self-describing — a verifier or a player
  recovering on a fresh device needs nothing but the message and their
  identity secret:

      %{
        "salt" => "catenary:bg:chain",
        "n" => 1024, "r" => 8, "p" => 1, "keylen" => 32,
        "length" => 256
      }

  The derivation recipes above are fixed protocol facts that consume the
  spec; the spec itself only carries the parameters.
  """

  @salt "catenary:bg:chain"
  @n 1024
  @r 8
  @p 1
  @keylen 32
  @length 256

  @doc """
  The standard chain spec: a single flat map of every variable constant.
  The salt is fixed (`"catenary:bg:chain"`) to namespace the derivation; the
  per-game domain separation comes from the game ID mixed into the seed (see
  `seed_for/4`), so no random per-game salt is needed.

  ## Examples

      iex> spec = Catenary.Backgammon.Chain.spec()
      iex> spec["salt"]
      "catenary:bg:chain"

      iex> Catenary.Backgammon.Chain.spec()["length"]
      256

  """
  @spec spec() :: map()
  def spec do
    %{
      "salt" => @salt,
      "n" => @n,
      "r" => @r,
      "p" => @p,
      "keylen" => @keylen,
      "length" => @length
    }
  end

  @doc """
  Derive the next chain value from a previous one.

  Returns a 32-byte binary.

  ## Examples

      iex> prev = :crypto.hash(:sha256, "seed")
      iex> next = Catenary.Backgammon.Chain.derive(prev)
      iex> byte_size(next)
      32

  """
  @spec derive(binary(), map()) :: binary()
  def derive(prev, spec \\ spec()) when is_binary(prev) and byte_size(prev) == 32 do
    Scrypt.scrypt(prev, spec["salt"], spec["n"], spec["r"], spec["p"], spec["keylen"])
  end

  @doc """
  Derive the recoverable chain seed for a game from an identity secret.

  `role` is `"challenger"` or `"accepter"`. The derivation is deterministic,
  so a player on a fresh device can regenerate the exact chain they committed
  to using only the game id and their role from the log.

  ## Examples

      iex> secret = :crypto.strong_rand_bytes(32)
      iex> game_id = :crypto.strong_rand_bytes(32)
      iex> seed = Catenary.Backgammon.Chain.seed_for(secret, game_id, "challenger")
      iex> byte_size(seed)
      32

  """
  @spec seed_for(binary(), binary(), String.t(), map()) :: binary()
  def seed_for(identity_secret, game_id, role, spec \\ spec())
      when is_binary(identity_secret) and is_binary(game_id) and is_binary(role) do
    Scrypt.scrypt(
      identity_secret,
      spec["salt"] <> ":seed:" <> game_id <> ":" <> role,
      spec["n"],
      spec["r"],
      spec["p"],
      spec["keylen"]
    )
  end

  @doc """
  Generate a chain of `spec["length"]` values from a seed.

  Returns a list of 32-byte binaries, ordered from the seed onward.
  The first element is `derive(seed)`, not the seed itself — the seed
  is never part of the published chain.

  ## Examples

      iex> seed = :crypto.strong_rand_bytes(32)
      iex> spec = %{Catenary.Backgammon.Chain.spec() | "length" => 5}
      iex> chain = Catenary.Backgammon.Chain.generate(seed, spec)
      iex> length(chain)
      5

  """
  @spec generate(binary(), map()) :: [binary()]
  def generate(seed, spec \\ spec()) when is_binary(seed) do
    length = spec["length"]

    if length == 1 do
      [derive(seed, spec)]
    else
      first = derive(seed, spec)

      Enum.reduce(2..length, [first], fn _, acc ->
        [next | _] = acc
        [derive(next, spec) | acc]
      end)
      |> Enum.reverse()
    end
  end

  @doc """
  Read a player's cached chain out of a game row.

  Generated chains are memoised on the game's `{:game, game_id}` row in the
  `:challenges` index table — field `:chains`, a `%{role => chain}` map — so
  the same ~10s scrypt build is reused across a game instead of restarting on
  every roll. The full chain is the player's *future* reveals: this is a
  node-local cache and never enters a log; only the two per-turn reveals a
  published roll/turn entry carries leave the node.
  """
  @spec cache_get(map(), String.t()) :: [binary()] | nil
  def cache_get(game, role) when is_map(game) and is_binary(role) do
    game |> Map.get(:chains, %{}) |> Map.get(role)
  end

  @doc """
  Store a cached chain on the game row (read-modify-write, keeping any other
  role's chain already present). A missing row is a no-op.
  """
  @spec cache_put(String.t(), String.t(), [binary()]) :: :ok
  def cache_put(game_id, role, chain)
      when is_binary(game_id) and is_binary(role) and is_list(chain) do
    key = {:game, game_id}

    case :ets.lookup(:challenges, key) do
      [{^key, row}] ->
        chains = row |> Map.get(:chains, %{}) |> Map.put(role, chain)
        :ets.insert(:challenges, {key, Map.put(row, :chains, chains)})
        :ok

      _ ->
        :ok
    end
  end

  @doc """
  Compute the commitment for a chain.

  The commitment is `SHA-256(last_value)` — the SHA-256 hash of the final
  element in the chain.  Publish this before the game begins.

  Pass the full chain (list of 32-byte binaries) or just the last element.

  ## Examples

      iex> chain = for _ <- 1..3, do: :crypto.strong_rand_bytes(32)
      iex> commitment = Catenary.Backgammon.Chain.commit(chain)
      iex> byte_size(commitment)
      32

  """
  @spec commit([binary()] | binary()) :: binary()
  def commit(chain) when is_list(chain) do
    chain |> List.last() |> commit()
  end

  def commit(value) when is_binary(value) and byte_size(value) == 32 do
    :crypto.hash(:sha256, value)
  end

  @doc """
  Derive two dice values from both players' revealed chain values.

  `my_value` is the revealed value being used for the mover's turn;
  `opp_value` is the opponent's freshly-revealed value for the same turn.
  Both must be 32-byte binaries.

  Returns `{die1, die2}` where each is an integer in `1..6`.

  The derivation is deterministic and order matters (the mover's half is
  first), so both players and any verifier recompute the identical roll.

  ## Unbiasedness

  The 32-byte SHA-256 hash gives 256 bits of entropy. Each byte is in
  `0..255`; mapping `rem(byte, 6)` introduces a tiny bias because 256 is
  not divisible by 6 (values 1–4 would appear 43 times, 5–6 only 42).

  To eliminate this, we use **rejection sampling** over the hash bytes:
  a byte in `0..251` maps to 1..6 via `rem(byte, 6) + 1` (exactly 42 values
  per outcome, perfectly uniform). Bytes `252..255` are rejected and the
  next byte tried. With 32 bytes and a rejection probability of only
  `4/256 ≈ 1.56%` per byte, the expected number of bytes consumed per die
  is `256/252 ≈ 1.016`, so the 32-byte hash is sufficient with overwhelming
  probability. Should the astronomically unlikely case arise of exhausting
  all 32 bytes without finding two valid ones (probability ~10⁻⁵⁸), the
  hash is re-hashed and the scan restarts — still deterministic and
  reproducible from the same inputs.

  ## Examples

      iex> a = :crypto.strong_rand_bytes(32)
      iex> b = :crypto.strong_rand_bytes(32)
      iex> [d1, d2] = Catenary.Backgammon.Chain.dice(a, b)
      iex> d1 in 1..6 and d2 in 1..6
      true

  """
  @spec dice(binary(), binary(), pos_integer()) :: [pos_integer()]
  def dice(my_value, opp_value, count \\ 2)
      when is_binary(my_value) and byte_size(my_value) == 32 and
             is_binary(opp_value) and byte_size(opp_value) == 32 and
             is_integer(count) and count >= 1 do
    extract_dice([], %{hash_next: my_value <> opp_value, found: [], needed: count})
  end

  @doc false
  # All dice found — done. We keep them in order for reproducibility
  def extract_dice(_hash, %{needed: 0, found: f}), do: Enum.reverse(f)
  # No hash left to extract, gen next
  def extract_dice([], %{hash_next: hn} = acc) do
    hash = :crypto.hash(:sha256, hn)
    extract_dice(:binary.bin_to_list(hash), %{acc | hash_next: hash})
  end

  # Next byte to extract is rejected, since its inclusion would bias the results
  def extract_dice([fb | rest], acc) when fb >= 252, do: extract_dice(rest, acc)
  # Next byte produces a die
  def extract_dice([fb | rest], %{needed: n, found: f} = acc) do
    die = rem(fb, 6) + 1
    extract_dice(rest, %{acc | found: [die | f], needed: n - 1})
  end

  @doc """
  The next reveal pair for a player, indexed from how much entropy is left.

  `remaining` is the number of untouched reveals (counts down from the chain
  length; the accepter starts one lower because their accept reveal consumes
  `chain[-1]`). Returns `{r_cur, r_next}` — the half that mixes into the next
  roll and the freshly-announced next half. Acting requires `remaining >= 2`;
  a remaining of `0` means the chain is spent.

  ## Examples

      iex> spec = %{Catenary.Backgammon.Chain.spec() | "length" => 5}
      iex> chain = Catenary.Backgammon.Chain.generate(:crypto.strong_rand_bytes(32), spec)
      iex> {r_cur, r_next} = Catenary.Backgammon.Chain.reveal_pair(chain, 5)
      iex> [c1, c2 | _] = Enum.reverse(chain)
      iex> {r_cur, r_next} == {c1, c2}
      true

  """
  @spec reveal_pair([binary()], integer(), map() | nil) :: {binary(), binary()}
  def reveal_pair(chain, remaining, spec \\ nil)
      when is_list(chain) and is_integer(remaining) and remaining >= 2 do
    len = if is_map(spec), do: spec["length"], else: length(chain)
    # Reveals walk the chain tail-first, so reverse once and drop the values
    # already consumed. `remaining` says how many are untouched; the head of
    # what's left is the reveal for the next roll, the next the opponent's.
    [r_cur, r_next | _] = Enum.drop(Enum.reverse(chain), len - remaining)
    {r_cur, r_next}
  end

  @doc """
  Verify the first reveal of a chain against its commitment.

  The first reveal is `chain[-1]`; its SHA-256 must equal the published
  commitment.

  Returns `:ok` or `{:error, reason}`.

  ## Examples

      iex> seed = :crypto.strong_rand_bytes(32)
      iex> chain = Catenary.Backgammon.Chain.generate(seed, %{Catenary.Backgammon.Chain.spec() | "length" => 10})
      iex> commit = Catenary.Backgammon.Chain.commit(chain)
      iex> Catenary.Backgammon.Chain.verify_first(List.last(chain), commit)
      :ok
      iex> Catenary.Backgammon.Chain.verify_first(:crypto.strong_rand_bytes(32), commit)
      {:error, "reveal does not match commitment"}

  """
  @spec verify_first(binary(), binary()) :: :ok | {:error, String.t()}
  def verify_first(revealed, commitment)
      when is_binary(revealed) and byte_size(revealed) == 32 and
             is_binary(commitment) and byte_size(commitment) == 32 do
    if commit(revealed) == commitment do
      :ok
    else
      {:error, "reveal does not match commitment"}
    end
  end

  @doc """
  Verify a subsequent reveal extends the chain backward from the previous one.

  Each reveal is the one-way preimage of the value revealed before it, so
  `derive(revealed)` must equal `prior_reveal`.

  Returns `:ok` or `{:error, reason}`.

  ## Examples

      iex> seed = :crypto.strong_rand_bytes(32)
      iex> short = %{Catenary.Backgammon.Chain.spec() | "length" => 10}
      iex> chain = Catenary.Backgammon.Chain.generate(seed, short)
      iex> [b, a | _] = Enum.reverse(chain)
      iex> Catenary.Backgammon.Chain.verify_next(a, b, short)
      :ok
      iex> Catenary.Backgammon.Chain.verify_next(
      ...>   :crypto.strong_rand_bytes(32), List.last(chain), short)
      {:error, "reveal does not extend the chain"}

  """
  @spec verify_next(binary(), binary(), map()) :: :ok | {:error, String.t()}
  def verify_next(revealed, prior_reveal, spec \\ spec())
      when is_binary(revealed) and byte_size(revealed) == 32 and
             is_binary(prior_reveal) and byte_size(prior_reveal) == 32 do
    if derive(revealed, spec) == prior_reveal do
      :ok
    else
      {:error, "reveal does not extend the chain"}
    end
  end
end
