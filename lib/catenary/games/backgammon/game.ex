defmodule Catenary.Games.Backgammon.Game do
  @moduledoc """
  Game identity, log derivation, and challenge messages for Catenary
  backgammon.

  ## Game identity

  A game is identified by a 32-byte `game_id` (chosen by the challenger).
  From this and both players' Baobab public keys, a 56-bit **game base** is
  derived deterministically:

      game_base = SHA-256(challenger_pk <> accepter_pk <> game_id)[0..6]

  Each player writes to their own Baobab log at:

      log_id = game_base | (device_facet << 56)

  The high 8 bits are reserved for per-device facets, leaving 2^56 log
  positions per device — effectively unbounded for game play.

  ## Chain spec

  The challenge message carries the full provably-fair chain spec (see
  `Chain.spec/0`), so it is self-describing: both the
  accepter and any verifier — or the player recovering on a fresh device —
  need nothing beyond the message and their identity secret.
  """

  alias Catenary.Games.Backgammon.Chain

  @chain_length Catenary.Games.Backgammon.Chain.spec()["length"]

  @doc """
  The chain spec that travels with challenge and accept messages.

  Delegates to `Chain.spec/0` so entries and the chain
  implementation always agree on the constants.
  """
  @spec chain_spec() :: map()
  def chain_spec do
    Chain.spec()
  end

  @doc """
  Compute the reserved-range game base from two Baobab public keys, a game ID,
  and a family tag.

  Both keys should be base62-encoded strings (as returned by
  `Baobab.Identity.as_base62/1`).  The game ID is a 32-byte binary. The
  `family` is the derived-log family tag (a byte in `1..255`, defaulting to
  the backgammon family).

  The derived value is folded into the **reserved** base-log range by
  `QuaggaDef.derived_log_base/2`, so it can never collide with a
  hand-allocated log ID (all of which live in the low 48 bits), and the
  family tag in bits 48..55 discriminates the game ruleset.

  Returns a non-negative integer with the reserved high byte set
  (`>= 2^48`).

  ## Examples

      iex> pk1 = "abc123"
      iex> pk2 = "def456"
      iex> game_id = :crypto.strong_rand_bytes(32)
      iex> base = Catenary.Games.Backgammon.Game.game_base(pk1, pk2, game_id)
      iex> QuaggaDef.reserved_base_log?(base)
      true

      iex> QuaggaDef.family_for_block(
      ...>   Catenary.Games.Backgammon.Game.game_base("abc123", "def456", :crypto.strong_rand_bytes(32))
      ...> )
      :backgammon

  """
  @spec game_base(String.t(), String.t(), binary(), 1..255) :: non_neg_integer()
  def game_base(challenger_pk, accepter_pk, game_id, family \\ QuaggaDef.family_tag(:backgammon))
      when is_binary(challenger_pk) and is_binary(accepter_pk) and
             is_binary(game_id) and byte_size(game_id) == 32 do
    <<gb::unsigned-little-48, _::binary>> =
      :crypto.hash(:sha256, challenger_pk <> accepter_pk <> game_id)

    QuaggaDef.derived_log_base(gb, family)
  end

  @doc """
  Compute a player's game log ID from the game base and a device facet.

  The facet occupies the high 8 bits of the 64-bit log ID, giving each
  device its own log within the game. The game base carries the reserved
  range marker, so the resulting log ID is always in the derived/reserved
  part of the namespace.

  ## Examples

      iex> Catenary.Games.Backgammon.Game.game_log_id(0, 0)
      0

      iex> Catenary.Games.Backgammon.Game.game_log_id(0, 1)
      0x0100000000000000

  """
  @spec game_log_id(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def game_log_id(game_base, device_facet)
      when is_integer(game_base) and game_base >= 0 and game_base < Bitwise.bsl(1, 56) and
             is_integer(device_facet) and device_facet >= 0 and device_facet <= 255 do
    Bitwise.bor(game_base, Bitwise.bsl(device_facet, 56))
  end

  @doc """
  Build a challenge entry for the `:challenge` log (777).

  This is published by the challenger to initiate a game.

  The entry is self-describing: it carries the full chain spec (`chain_spec`)
  pinning every provably-fair constant (scrypt parameters and the committed
  chain length), so anyone — including the eventual accepter or the
  challenger recovering on a fresh device — can reproduce or verify the
  chain from this message alone.

  ## Keys

  * `"type"` — `"challenge"`
  * `"game_id"` — raw 32-byte game ID (CBOR byte string; encoded for display
    elsewhere, never in the entry itself)
  * `"family"` — derived-log family tag byte (e.g. 1 = backgammon)
  * `"player"` — challenger's base62 public key
  * `"to"` — optional addressee's base62 public key; when present only that
    player may accept, otherwise the challenge is open to anyone
  * `"chain_spec"` — the full provably-fair spec (scrypt params + length)
  * `"chain_commit"` — hex-encoded SHA-256 commitment to the chain, or `nil`
    for games that don't use provably-fair dice
  * `"role"` — `"challenger"`; together with the game id it selects which
    chain a fresh device regenerates

  """
  @spec challenge_entry(
          String.t(),
          binary(),
          1..255,
          binary() | nil,
          map() | nil,
          String.t() | nil
        ) ::
          map()
  def challenge_entry(player, game_id, family, chain_commit \\ nil, chain_spec \\ nil, to \\ nil)
      when is_binary(player) and is_binary(game_id) and
             byte_size(game_id) == 32 and
             (is_nil(chain_commit) or byte_size(chain_commit) == 32) do
    entry = %{
      "type" => "challenge",
      "game_id" => game_id,
      "family" => family,
      "player" => player,
      "role" => "challenger",
      "chain_spec" => chain_spec || chain_spec(),
      "chain_commit" => maybe_hex(chain_commit)
    }

    case to do
      nil -> entry
      _ -> Map.put(entry, "to", to)
    end
  end

  @doc """
  Build an accept entry for the `:challenge` log (777).

  This is published by the accepter to confirm the game.

  It echoes the challenger's chain spec so each player's own authored
  message stays self-contained, commits to the accepter's chain, and
  carries the accepter's **first reveal** (`"reveal"`) — `chain[-1]` — so the
  challenger's opening turn has both dice halves available before play
  begins.

  ## Keys

  * `"type"` — `"accept"`
  * `"game_id"` — raw 32-byte game ID (CBOR byte string)
  * `"family"` — derived-log family tag byte (e.g. 1 = backgammon)
  * `"player"` — accepter's base62 public key
  * `"chain_spec"` — the echoed chain spec
  * `"chain_commit"` — hex-encoded SHA-256 commitment to the accepter's chain
  * `"role"` — `"accepter"`; together with the game id it selects which
    chain a fresh device regenerates
  * `"reveal"` — hex-encoded first chain value (`chain[-1]`), or `nil`

  """
  @spec accept_entry(String.t(), binary(), 1..255, binary() | nil, map() | nil, binary() | nil) ::
          map()
  def accept_entry(player, game_id, family, chain_commit \\ nil, chain_spec \\ nil, reveal \\ nil)
      when is_binary(player) and is_binary(game_id) and
             byte_size(game_id) == 32 and
             (is_nil(chain_commit) or byte_size(chain_commit) == 32) and
             (is_nil(reveal) or byte_size(reveal) == 32) do
    %{
      "type" => "accept",
      "game_id" => game_id,
      "family" => family,
      "player" => player,
      "role" => "accepter",
      "chain_spec" => chain_spec || chain_spec(),
      "chain_commit" => maybe_hex(chain_commit),
      "reveal" => maybe_hex(reveal)
    }
  end

  @doc """
  Build the accepter's kickoff entry for the game's play log (a derived log).

  Published by the accepter at accept time, in addition to the `accept` entry
  on the challenge log (777). It is written on the accepter's own device
  facet (`game_log_id`) and makes the play stream **self-contained**: a device
  that finds the play log without indexing 777 can still reconstruct the whole
  game, because this entry carries every piece of game context — both players,
  the family tag, the chain spec, both chain commitments, and the accepter's
  first reveal (the dice half that mixes with the challenger's first half on
  the opening turn).

  ## Keys

  * `"type"` — `"play"`
  * `"game_id"` — raw 32-byte game ID (CBOR byte string)
  * `"family"` — derived-log family tag byte (e.g. 1 = backgammon)
  * `"player"` — accepter's base62 public key
  * `"role"` — `"accepter"`
  * `"challenger"` — challenger's base62 public key
  * `"chain_spec"` — the echoed chain spec
  * `"chain_commit"` — hex-encoded SHA-256 commitment to the accepter's chain
  * `"challenger_commit"` — hex-encoded SHA-256 commitment to the challenger's chain
  * `"reveal"` — hex-encoded first accepter chain value (`chain[-1]`), or `nil`
  * `"game_base"` — the derived base both players write on
  * `"game_log_id"` — the exact log ID the entry was appended to (base plus
    the writer's device facet)

  """
  @spec play_entry(
          String.t(),
          binary(),
          1..255,
          String.t(),
          non_neg_integer(),
          keyword()
        ) :: map()
  def play_entry(player, game_id, family, challenger, game_base, opts \\ [])
      when is_binary(player) and is_binary(game_id) and
             byte_size(game_id) == 32 and is_binary(challenger) and
             is_integer(game_base) and game_base >= 0 do
    %{
      "type" => "play",
      "game_id" => game_id,
      "family" => family,
      "player" => player,
      "role" => "accepter",
      "challenger" => challenger,
      "chain_spec" => Keyword.get(opts, :chain_spec, chain_spec()),
      "chain_commit" => maybe_hex(Keyword.get(opts, :chain_commit)),
      "challenger_commit" => maybe_hex(Keyword.get(opts, :challenger_commit)),
      "reveal" => maybe_hex(Keyword.get(opts, :reveal)),
      "game_base" => game_base,
      "game_log_id" => Keyword.get(opts, :game_log_id)
    }
  end

  defp maybe_hex(nil), do: nil
  defp maybe_hex(bin), do: Base.encode16(bin, case: :lower)

  @doc """
  Build a turn entry for the game's play log (a derived log).

  Published by the mover after each turn. The entry is self-contained: it
  carries the raw `game_id`, the player, the sequential `turn` number, the
  canonical `roll` string, the `moves` in Magriel notation, and the two
  fresh chain reveals — `r_cur`, the mover's half that mixed into **this**
  roll, and `r_next`, the half the opponent's next roll will be mixed with.

  ## Keys

  * `"type"` — `"turn"`
  * `"game_id"` — raw 32-byte game ID (CBOR byte string)
  * `"player"` — mover's base62 public key
  * `"turn"` — sequential turn number, 1-indexed (the first turn is `1`),
    **independent** of the reveal counter
  * `"roll"` — canonical roll `"min-max"` (doubles render `"3-3"`)
  * `"moves"` — Magriel motion capture, e.g. `"13/8 13/8"`
  * `"r_cur"`, `"r_next"` — hex-encoded reveal values (previous two chain
    entries in the mover's chain)
  * `"reveals"` — reveals *remaining* before this entry, counting down from
    the chain length (the accepter starts one lower, their accept reveal
    consumed `chain[-1]`); `0` means the chain is spent
  * `"note"` — optional player annotation attached to the entry

  """
  @spec turn_entry(
          String.t(),
          binary(),
          pos_integer(),
          String.t(),
          String.t(),
          binary(),
          binary(),
          keyword()
        ) :: map()
  def turn_entry(player, game_id, turn, roll, moves, r_cur, r_next, opts \\ [])
      when is_binary(player) and is_binary(game_id) and byte_size(game_id) == 32 and
             is_integer(turn) and turn >= 1 and is_binary(roll) and is_binary(moves) and
             byte_size(r_cur) == 32 and byte_size(r_next) == 32 do
    %{
      "type" => "turn",
      "game_id" => game_id,
      "player" => player,
      "turn" => turn,
      "roll" => roll,
      "moves" => moves,
      "r_cur" => Base.encode16(r_cur, case: :lower),
      "r_next" => Base.encode16(r_next, case: :lower),
      "reveals" => Keyword.get(opts, :reveals, @chain_length),
      "note" => Keyword.get(opts, :note, "")
    }
  end

  @doc """
  An opening-roll entry: one player revealing their half of an opening round.

  Opening rounds alternate `challenger` then `accepter`; a round completes
  when both halves are in, and its dice — `Chain.dice(round_challenger_half,
  round_accepter_half)` — pick the starter (higher die; ties re-roll with the
  next round). `round` is 0-indexed, `reveals` the remaining reveal count.

  ## Keys

  * `"type"` — `"roll"`
  * `"game_id"` — raw 32-byte game ID (CBOR byte string)
  * `"player"` — the rolling player's base62 public key
  * `"round"` — opening round this entry belongs to, 0-indexed
  * `"reveals"` — reveals remaining before this entry, counting down
  * `"r_cur", "r_next"` — hex reveal values
  * `"note"` — optional note

  """
  @spec roll_entry(
          String.t(),
          binary(),
          non_neg_integer(),
          pos_integer(),
          binary(),
          binary(),
          keyword()
        ) :: map()
  def roll_entry(player, game_id, round, reveals, r_cur, r_next, opts \\ [])
      when is_binary(player) and is_binary(game_id) and byte_size(game_id) == 32 and
             is_integer(round) and round >= 0 and is_integer(reveals) and reveals >= 2 and
             byte_size(r_cur) == 32 and byte_size(r_next) == 32 do
    %{
      "type" => "roll",
      "game_id" => game_id,
      "player" => player,
      "round" => round,
      "reveals" => reveals,
      "r_cur" => Base.encode16(r_cur, case: :lower),
      "r_next" => Base.encode16(r_next, case: :lower),
      "note" => Keyword.get(opts, :note, "")
    }
  end

  @doc """
  The roll string: the two dice joined with a hyphen (`"3-5"`, `"5-3"`,
  `"4-4"`).  Order is preserved from the arguments; `check_roll` in the
  fold accepts both orderings for verification.

  ## Examples

      iex> Catenary.Games.Backgammon.Game.roll_string(3, 5)
      "3-5"

      iex> Catenary.Games.Backgammon.Game.roll_string(5, 3)
      "5-3"

      iex> Catenary.Games.Backgammon.Game.roll_string(4, 4)
      "4-4"

  """
  @spec roll_string(1..6, 1..6) :: String.t()
  def roll_string(a, b) when a in 1..6 and b in 1..6 do
    [a, b] |> Enum.map_join("-", &Integer.to_string/1)
  end

  @doc """
  Parse the canonical roll string back into `{d1, d2}`.

  ## Examples

      iex> Catenary.Games.Backgammon.Game.parse_roll("3-5")
      {3, 5}

      iex> Catenary.Games.Backgammon.Game.parse_roll("4-4")
      {4, 4}

  """
  @spec parse_roll(String.t()) :: {1..6, 1..6}
  def parse_roll(string) when is_binary(string) do
    case string |> String.split("-") |> Enum.map(&String.to_integer/1) do
      [a, b] when a in 1..6 and b in 1..6 -> {a, b}
    end
  end

  @doc """
  A resign entry: the mover concedes the game.

  The winner is the opponent of the resigner. No chain reveals are consumed —
  resign does not involve rolling dice. The `"turn"` field is the turn the
  resigner is declining (turn_count + 1 at the time of resign).

  ## Keys

  * `"type"` — `"resign"`
  * `"game_id"` — raw 32-byte game ID (CBOR byte string)
  * `"player"` — the resigning player's base62 public key
  * `"turn"` — the turn being declined (turn_count + 1)
  * `"note"` — optional player annotation

  """
  @spec resign_entry(String.t(), binary(), pos_integer(), keyword()) :: map()
  def resign_entry(player, game_id, turn, opts \\ [])
      when is_binary(player) and is_binary(game_id) and byte_size(game_id) == 32 and
             is_integer(turn) and turn >= 1 do
    %{
      "type" => "resign",
      "game_id" => game_id,
      "player" => player,
      "turn" => turn,
      "note" => Keyword.get(opts, :note, "")
    }
  end
end
