defmodule Catenary.Backgammon.GameReplayTest do
  use ExUnit.Case, async: true

  alias Catenary.Backgammon.{Engine, Notation}

  # Magriel vs Svobodny from Bill Robertie's "Backgammon for Serious Players".
  # The transcript uses Black's perspective throughout (Robertie convention):
  # White's moves are in Black's coordinate system and must be mirrored to
  # White's Engine perspective before applying. Black's moves apply directly.
  # After each turn the position is mirrored for the next player.

  test "replay Magriel vs Svobodny complete game" do
    moves = [
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

    final_pos = replay_moves(Engine.initial(), moves)

    assert %Engine{} = final_pos
    total_self = Engine.checkers(final_pos)

    total_opp =
      final_pos.opp_bar + final_pos.opp_off +
        Enum.reduce(final_pos.points, 0, fn {_p, n}, acc -> acc + max(-n, 0) end)

    assert total_self + total_opp == 30
  end

  test "verify first two turns (White opening + Black response)" do
    pos = Engine.initial()

    # White's opening: transcript "1/7 12/14" in Black's coords.
    # Mirror position to White's view, mirror move coords, apply, mirror back.
    white_pos = Engine.mirror(pos)
    white_moves = Notation.parse("1/7 12/14") |> Enum.map(&mirror_move/1)
    after_white = Engine.mirror(Engine.apply(white_pos, white_moves))

    # Black's response: "8/7* 13/11" — already in Black's coords.
    black_play = Notation.parse("8/7 13/11")
    after_black = Engine.apply(after_white, black_play) |> Engine.mirror()

    total_self = Engine.checkers(after_black)

    total_opp =
      after_black.opp_bar + after_black.opp_off +
        Enum.reduce(after_black.points, 0, fn {_p, n}, acc -> acc + max(-n, 0) end)

    assert total_self + total_opp == 30
  end

  # -- helpers --

  defp replay_moves(initial_pos, moves) do
    Enum.reduce(moves, initial_pos, fn {player, _roll, moves_str}, pos ->
      clean_moves = String.replace(moves_str, "*", "")
      parsed_moves = Notation.parse(clean_moves)

      case player do
        :white ->
          white_pos = Engine.mirror(pos)
          white_moves = Enum.map(parsed_moves, &mirror_move/1)
          Engine.apply(white_pos, white_moves) |> Engine.mirror()

        :black ->
          Engine.apply(pos, parsed_moves) |> Engine.mirror()
      end
    end)
  end

  defp mirror_move({:bar, to}), do: {:bar, 25 - to}
  defp mirror_move({from, :off}), do: {25 - from, :off}
  defp mirror_move({from, to}), do: {25 - from, 25 - to}
end
