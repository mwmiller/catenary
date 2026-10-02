defmodule Catenary.IndexWorker.AliasesTest do
  use ExUnit.Case, async: false

  alias Catenary.IndexWorker.Aliases
  alias Catenary.Preferences

  # These two publish into the test clump, which persists across runs, so a
  # leftover identity from a run that died before its cleanup is dropped
  # rather than collided with: creating one returns a fresh key either way,
  # and entries left behind name keys nothing active can match.
  defp drop_identity(name) do
    if Enum.any?(Baobab.Identity.list(), fn {n, _} -> n == name end) do
      Baobab.Identity.drop(name)
    end
  end

  defp claim(published, whom, name) do
    %{"published" => published, "whom" => whom, "alias" => name}
  end

  defp aliases, do: elem(Catenary.alias_state(), 1)

  defp publish(author, fields) do
    fields
    |> Map.put_new("published", DateTime.utc_now() |> DateTime.to_string())
    |> CBOR.encode()
    |> Baobab.append_log(author,
      log_id: hd(QuaggaDef.logs_for_name(:alias)),
      clump_id: Preferences.get(:clump_id)
    )
  end

  defp reindex, do: GenServer.call(:aliases, :update)

  test "the newest claim for a name wins, in either order" do
    older = claim("2023-03-08 13:31:46.169694Z", "OldKey", "sosofetch")
    newer = claim("2026-10-02 17:58:07.520642Z", "NewKey", "sosofetch")

    expected = %{"NewKey" => "sosofetch"}

    assert Aliases.build([older, newer]) == expected
    assert Aliases.build([newer, older]) == expected
  end

  test "a name handed to a new key leaves the old key with none" do
    first = claim("2020-01-01 00:00:00.000000Z", "KeyA", "shared")
    later = claim("2021-01-01 00:00:00.000000Z", "KeyB", "shared")

    assert Aliases.build([first, later]) == %{"KeyB" => "shared"}
    assert Aliases.build([later, first]) == %{"KeyB" => "shared"}
  end

  test "one key may rename itself" do
    first = claim("2020-01-01 00:00:00.000000Z", "KeyA", "old")
    later = claim("2021-01-01 00:00:00.000000Z", "KeyA", "new")

    assert Aliases.build([first, later]) == %{"KeyA" => "new"}
    assert Aliases.build([later, first]) == %{"KeyA" => "new"}
  end

  test "a claim with no readable time is the oldest of them" do
    undated = claim(nil, "KeyA", "sosofetch")
    dated = claim("2026-10-02 17:58:07.520642Z", "KeyB", "sosofetch")

    assert Aliases.build([dated, undated]) == %{"KeyB" => "sosofetch"}
    assert Aliases.build([undated, dated]) == %{"KeyB" => "sosofetch"}
  end

  test "a claim carrying no key and name in text is skipped" do
    keep = claim("2020-01-01 00:00:00.000000Z", "KeyA", "keep")

    ignored = [
      %{"alias" => "nowhom"},
      %{"whom" => "KeyB"},
      claim("2020-01-01 00:00:00.000000Z", "KeyC", ""),
      claim("2020-01-01 00:00:00.000000Z", 42, "numbered"),
      "not even a map"
    ]

    assert Aliases.build([keep | ignored]) == %{"KeyA" => "keep"}
  end

  describe "the index folds the active identity's log and no other" do
    setup do
      original = Preferences.get(:identity)
      mine_name = "catenary-alias-test-mine"
      theirs_name = "catenary-alias-test-theirs"
      drop_identity(mine_name)
      drop_identity(theirs_name)
      mine = Baobab.Identity.create(mine_name)
      theirs = Baobab.Identity.create(theirs_name)

      # Restore the preference first: it has to name an identity that still
      # exists, and the reindex after it puts the map back the way this
      # test found it.
      on_exit(fn ->
        Preferences.set(:identity, original)
        reindex()
        Baobab.Identity.drop(mine_name)
        Baobab.Identity.drop(theirs_name)
      end)

      %{mine: mine, theirs: theirs, mine_name: mine_name, theirs_name: theirs_name}
    end

    test "a name another local identity set does not leak in", ctx do
      publish(ctx.theirs_name, %{"whom" => ctx.theirs, "alias" => "set-by-theirs"})
      publish(ctx.mine_name, %{"whom" => ctx.mine, "alias" => "set-by-mine"})

      Preferences.set(:identity, ctx.mine)
      reindex()
      assert aliases() == %{ctx.mine => "set-by-mine"}

      Preferences.set(:identity, ctx.theirs)
      reindex()
      assert aliases() == %{ctx.theirs => "set-by-theirs"}
    end
  end
end
