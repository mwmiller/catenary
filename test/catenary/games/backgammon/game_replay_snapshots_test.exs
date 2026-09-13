defmodule Catenary.Games.Backgammon.GameReplaySnapshotsTest do
  @moduledoc """
  Full game replay test with per-turn position snapshots.

  Replays the Magriel vs Svobodny game from Robertie's "Backgammon for
  Serious Players" and captures the position after each turn, verifying
  key position properties at every step.
  """
  use ExUnit.Case, async: true

  alias Catenary.Games.Backgammon.{Engine, Notation}

  # Magriel vs Svobodny — 20 turns from Robertie's transcript.
  # White's moves are in Black's coordinate system (Robertie convention).
  @moves [
    {:white, "6-2", "1/7 12/14"},
    {:black, "2-1", "8/7* 13/11"},
    {:white, "6-2", "bar/2 1/7*"},
    {:black, "2-1", "bar/23 8/7*"},
    {:white, "3-2", "bar/2 12/15"},
    {:black, "5-1", "13/8 6/5"},
    {:white, "3-1", "2/5* 2/3"},
    {:black, "3-1", "bar/22 6/5*"},
    {:white, "5-5", "bar/5* 12/22* 17/22"},
    {:black, "5-4", "bar/20 bar/21"},
    {:white, "3-2", "17/20* 19/21*"},
    {:black, "6-5", "bar/20*"},
    {:white, "6-4", "bar/4 14/20*"},
    {:black, "6-5", "bar/20*"},
    {:white, "4-3", "bar/4 17/20*"},
    {:black, "1-1", "bar/24 bar/23 6/5*"},
    {:white, "6-3", "bar/3 15/21"},
    {:black, "6-5", "13/7 11/6"},
    {:white, "5-3", "12/20"},
    {:black, "3-1", "13/10 6/5"}
  ]

  test "full game replay with per-turn position snapshots" do
    {positions, final_pos} = replay_with_snapshots(Engine.initial(), @moves)

    assert length(positions) == 20

    Enum.each(Enum.with_index(positions, 1), fn {pos, turn} ->
      assert %Engine{} = pos, "Turn #{turn}: not an Engine struct"
    end)

    assert %Engine{} = final_pos
    assert total_checkers(final_pos) == 30

    final_after_mirror = Engine.mirror(final_pos)
    total_after = total_checkers(final_after_mirror)
    assert total_after == 30, "Final mirrored position must have 30 checkers, got #{total_after}"
  end

  test "position snapshots are deterministic" do
    {positions1, _} = replay_with_snapshots(Engine.initial(), @moves)
    {positions2, _} = replay_with_snapshots(Engine.initial(), @moves)

    assert positions1 == positions2
  end

  test "intermediate positions have valid Engine structs" do
    {positions, _} = replay_with_snapshots(Engine.initial(), @moves)

    Enum.each(Enum.with_index(positions, 1), fn {pos, _turn} ->
      assert %Engine{} = pos
      assert is_map(pos.points)
      assert is_integer(pos.bar)
      assert is_integer(pos.opp_bar)
      assert is_integer(pos.off)
      assert is_integer(pos.opp_off)
    end)
  end

  # -- helpers --

  defp replay_with_snapshots(initial_pos, moves) do
    {positions, final_pos} =
      Enum.reduce(moves, {[], initial_pos}, fn {player, _roll, moves_str}, {acc, pos} ->
        clean_moves = String.replace(moves_str, "*", "")
        parsed_moves = Notation.parse(clean_moves)

        new_pos =
          case player do
            :white ->
              white_pos = Engine.mirror(pos)
              white_moves = Enum.map(parsed_moves, &mirror_move/1)
              Engine.apply(white_pos, white_moves) |> Engine.mirror()

            :black ->
              Engine.apply(pos, parsed_moves) |> Engine.mirror()
          end

        {acc ++ [new_pos], new_pos}
      end)

    {positions, final_pos}
  end

  defp total_checkers(pos) do
    pos.bar + pos.off + pos.opp_bar + pos.opp_off +
      Enum.reduce(pos.points, 0, fn {_p, n}, acc -> acc + abs(n) end)
  end

  defp mirror_move({:bar, to}), do: {:bar, 25 - to}
  defp mirror_move({from, :off}), do: {25 - from, :off}
  defp mirror_move({from, to}), do: {25 - from, 25 - to}
end
