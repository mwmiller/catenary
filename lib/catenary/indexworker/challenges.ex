defmodule Catenary.IndexWorker.Challenges do
  @name_atom :challenges

  use Catenary.IndexWorker.Common,
    name_atom: :challenges,
    indica: {"🎲", "▢"},
    logs: QuaggaDef.logs_for_name(:challenge)

  alias Catenary.Backgammon.Fold

  @moduledoc """
  Index of backgammon challenges.

  Walks the `:challenge` log (777) for every author and pairs `challenge`,
  `accept`, `turn` and `withdraw` entries by `game_id`, storing the current
  set of open/live games in the `:challenges` ETS table under the `:display`
  key.

  Each row describes one game:

      %{
        # Core challenge fields
        game_id: hex,
        family: 1..255,
        challenger: base62_pk,
        accepter: base62_pk | nil,
        to: base62_pk | nil,
        challenge_spec: map | nil,
        challenge_commit: hex | nil,
        accept_commit: hex | nil,
        turn_count: non_neg_integer(),
        withdrawn: boolean | nil,
        published: iso8601 | nil,

        # Accept/chain fields
        accept_reveal: hex | nil,
        chains: %{role => [binary()]},  # node-local cache, never published

        # Fold output (populated after accept)
        position: Engine.t(),
        mover: base62_pk | nil,
        winner: %{player: base62_pk, stake: pos_integer(), type: :single | :gammon | :backgammon} | nil,
        phase: :opening | :playing | :finished,
        opener: %{starter: base62_pk, dice: [integer()], rounds: non_neg_integer()} | nil,
        opp_for_next: base62_pk | nil,
        remaining: %{base62_pk => non_neg_integer()},
        last_note: String.t(),
        history: [history_item()],
        fold_error: String.t() | :none
      }

  Each `turn` entry increments `turn_count`. During the opening, the
  challenger and accepter alternate rolls; once the starter is decided,
  the starter moves on odd turns and the other player on even turns.

  Entries on the wire carry the game ID as a raw 32-byte CBOR byte string;
  it is hex-encoded here so the index, UI, and log-writer actions all share
  one stable string form. A game whose `to` is set is addressed to that
  single player (a "directed" challenge) and only they may accept it;
  `to: nil` is open to anyone.
  """

  def do_index(todo, clump_id, prev_seen) do
    build_index(todo, clump_id, prev_seen, %{})
  end

  # A manual reindex replaces the game table in place rather than emptying it
  # first: live game views never race a nil row, and the node-local scrypt
  # chain cache (which lives on the rows) isn't dropped. build_index/4 prunes
  # games that left the log once the full pass completes.
  def wipe_for_rebuild do
    Indices.empty_tables([:challenges])
    :ok
  end

  # Terminal case with no prior state: full fold (force_rebuild or first index).
  defp build_index([], clump_id, %{} = _prev, _new) do
    games =
      :ets.match_object(@name_atom, :"$1")
      |> Enum.reduce(%{}, fn {key, game}, acc ->
        case key do
          {:game, _} -> Map.put(acc, key, game)
          _ -> acc
        end
      end)

    folded =
      Enum.map(games, fn {key, game} -> {key, fold_row(key, game, clump_id)} end)
      |> Map.new()

    :ets.insert(@name_atom, Map.to_list(folded))

    :ets.insert(
      @name_atom,
      {:display,
       folded
       |> Map.values()
       |> Enum.map(&Map.delete(&1, :chains))
       |> Enum.sort_by(& &1.published, :desc)}
    )

    seen = Map.new(Enum.map(games, fn {{:game, gid}, _} -> {gid, true} end))

    if Process.get(:challenges_full_rebuild, false) do
      Process.delete(:challenges_full_rebuild)
      prune_stale(seen)
    end

    seen
  end

  # Terminal case with prior state: only refold games touched by new entries.
  # `prev` is the cumulative seen map from the previous update. `new` tracks
  # which games had entries processed in this update — only those get refolded.
  defp build_index([], clump_id, prev, new) do
    games =
      :ets.match_object(@name_atom, :"$1")
      |> Enum.reduce(%{}, fn {key, game}, acc ->
        case key do
          {:game, _} -> Map.put(acc, key, game)
          _ -> acc
        end
      end)

    {to_refold, cached} =
      Enum.split_with(Map.to_list(games), fn {{:game, gid}, _} ->
        Map.has_key?(new, gid)
      end)

    refolded =
      Enum.map(to_refold, fn {key, game} -> {key, fold_row(key, game, clump_id)} end)
      |> Map.new()

    folded = Map.merge(Map.new(cached), refolded)

    :ets.insert(@name_atom, Map.to_list(folded))

    :ets.insert(
      @name_atom,
      {:display,
       folded
       |> Map.values()
       |> Enum.map(&Map.delete(&1, :chains))
       |> Enum.sort_by(& &1.published, :desc)}
    )

    all_games = Map.new(Enum.map(games, fn {{:game, gid}, _} -> {gid, true} end))
    Map.merge(prev, all_games)
  end

  defp build_index([{a, l, _} | rest], clump_id, prev, new) do
    new =
      entries_index(
        Enum.reverse(Baobab.full_log(a, log_id: l, clump_id: clump_id)),
        clump_id,
        new
      )

    build_index(rest, clump_id, prev, new)
  end

  defp entries_index([], _, seen), do: seen

  defp entries_index([entry | rest], clump_id, seen) do
    %Baobab.Entry{payload: payload} = entry
    {:ok, data, ""} = CBOR.decode(payload)

    seen =
      case data do
        %{"type" => "challenge", "game_id" => raw} = entry when byte_size(raw) == 32 ->
          gid = hex_id(raw)

          with {:ok, player} <- Map.fetch(entry, "player"),
               {:ok, cc} <- Map.fetch(entry, "chain_commit"),
               {:ok, family} <- fetch_family(entry) do
            put_open_game(gid,
              challenger: player,
              family: family,
              to: Map.get(entry, "to"),
              challenge_spec: Map.get(entry, "chain_spec"),
              challenge_commit: cc,
              published: data["published"]
            )

            Map.put(seen, gid, true)
          else
            _ -> seen
          end

        %{"type" => "accept", "game_id" => raw} = entry when byte_size(raw) == 32 ->
          gid = hex_id(raw)

          with {:ok, player} <- Map.fetch(entry, "player"),
               {:ok, cc} <- Map.fetch(entry, "chain_commit"),
               {:ok, family} <- fetch_family(entry) do
            put_open_game(gid,
              accepter: player,
              family: family,
              accept_commit: cc,
              accept_reveal: Map.get(entry, "reveal"),
              published: data["published"]
            )

            Map.put(seen, gid, true)
          end

        %{"type" => "withdraw", "game_id" => raw} when byte_size(raw) == 32 ->
          gid = hex_id(raw)
          :ets.insert(@name_atom, {{:game, gid}, Map.put(open_game(gid), :withdrawn, true)})
          Map.put(seen, gid, true)

        _ ->
          seen
      end

    entries_index(rest, clump_id, seen)
  end

  # Games whose gid no longer appears in any challenge log in the store.
  defp prune_stale(seen) do
    :ets.match_object(@name_atom, {{:game, :"$1"}, :"$2"})
    |> Enum.each(fn {{:game, gid}, _} ->
      case Map.has_key?(seen, gid) do
        true -> :ok
        false -> :ets.delete(@name_atom, {:game, gid})
      end
    end)
  end

  # Fold an accepted game's play log onto its row (position, mover, opponent
  # half, history) and carry the in-memory `:chains` cache across rebuilds —
  # it is node-local and never part of the log.
  #
  # Completed games (winner set) are never refolded — their state is final
  # and the scrypt chain verification is expensive.
  defp fold_row(key, game, clump_id) do
    chains =
      case :ets.lookup(@name_atom, key) do
        [{_, prev}] -> Map.get(prev, :chains, %{})
        [] -> %{}
      end

    if game.accepter != nil and Map.get(game, :challenger) != nil and
         Map.get(game, :winner) == nil do
      fold_opts = %{clump_id: clump_id}

      fold_opts =
        case Map.get(game, :accept_reveal) do
          reveal when is_binary(reveal) -> Map.put(fold_opts, :accept_reveal, reveal)
          _ -> fold_opts
        end

      fold = Fold.fold_game(game, fold_opts)

      game
      |> Map.merge(%{
        position: fold.position,
        turn_count: fold.turn_count,
        mover: fold.mover,
        winner: fold.winner,
        phase: fold.phase,
        opener: fold.opener,
        opp_for_next: fold.opp_for_next,
        remaining: fold.remaining,
        last_note: Map.get(fold, :last_note, ""),
        history: fold.history,
        fold_error: fold.error
      })
      |> Map.put(:chains, chains)
    else
      # Either no accepter yet (open) or already completed — carry chains
      # but skip the expensive fold.
      Map.put(game, :chains, chains)
    end
  end

  defp put_open_game(gid, fields) do
    :ets.insert(@name_atom, {{:game, gid}, Map.merge(open_game(gid), Map.new(fields))})
  end

  @doc """
  The current index row for a game by hex `game_id`, or `nil` when the index
  hasn't seen it. Accepted games carry the folded position/turn state.
  """
  def game(gid) when is_binary(gid) do
    case :ets.lookup(@name_atom, {:game, gid}) do
      [{_, game}] -> game
      [] -> nil
    end
  end

  defp open_game(gid) do
    case :ets.lookup(@name_atom, {:game, gid}) do
      [] ->
        %{
          game_id: gid,
          published: nil,
          withdrawn: nil,
          accepter: nil,
          to: nil,
          challenge_spec: nil,
          challenge_commit: nil,
          accept_commit: nil,
          accept_reveal: nil,
          turn_count: 0,
          chains: %{}
        }

      [{_, game}] ->
        game
    end
  end

  defp fetch_family(entry) do
    case Map.fetch(entry, "family") do
      {:ok, family} when is_integer(family) and family >= 1 and family <= 255 -> {:ok, family}
      _ -> :error
    end
  end

  # Wire entries carry the game ID as raw 32 bytes (enforced by the clause
  # guards above); the index keys and display rows use the hex form.
  defp hex_id(bin), do: Base.encode16(bin, case: :lower)
end
