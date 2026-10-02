defmodule Catenary.IndexWorker.ListingsTest do
  use ExUnit.Case, async: false

  alias Catenary.Preferences

  # Publishing goes into the test clump, which persists across runs, so
  # every test here has to leave the control log with no live listing at
  # its head: a `delist` is outranked by the next run's `listing`, but a
  # leftover `listing` would leak into whichever test runs next, and into
  # the view tests that expect an empty explorer.
  defp publish(fields) do
    identity = Preferences.get(:identity)

    fields
    |> Map.put_new("published", DateTime.utc_now() |> DateTime.to_string())
    |> CBOR.encode()
    |> Baobab.append_log(Catenary.id_for_key(identity),
      log_id: QuaggaDef.facet_log(Catenary.Apps.control_log(), Preferences.get(:facet_id)),
      clump_id: Preferences.get(:clump_id)
    )
  end

  # The worker's `:update` call is synchronous, so the index is settled by
  # the time this returns rather than somewhere after the assertions.
  defp reindex, do: GenServer.call(:listings, :update)

  defp display do
    case :ets.lookup(:listings, :display) do
      [{:display, rows}] -> rows
      _ -> []
    end
  end

  test "a valid listing is indexed, junk is not, and a delist removes it" do
    # None of these can become a row: an illegal slug, a family the
    # control log does not announce, a listing with no `v`, an entry that
    # names no family, and a type nothing dispatches on.
    publish(%{"type" => "listing", "family" => 2, "slug" => "Bad-Slug", "v" => 1})
    publish(%{"type" => "listing", "family" => 9, "slug" => "other-family", "v" => 1})
    publish(%{"type" => "listing", "family" => 2, "slug" => "no-version"})
    publish(%{"type" => "listing", "slug" => "no-family", "v" => 1})
    publish(%{"type" => "shuffle", "family" => 2, "slug" => "wrong-type", "v" => 1})

    publish(%{"type" => "listing", "family" => 2, "slug" => "example-app", "v" => 7})
    reindex()

    pk = Preferences.get(:identity)
    assert [%{pk: ^pk, slug: "example-app", family: 2, version: 7}] = display()
    assert [{_key, %{version: 7}}] = :ets.lookup(:listings, {pk, "example-app"})

    publish(%{"type" => "delist", "family" => 2, "slug" => "example-app"})
    reindex()

    assert display() == []
    assert :ets.lookup(:listings, {pk, "example-app"}) == []
  end

  test "whatever is at the head of the log wins" do
    publish(%{"type" => "listing", "family" => 2, "slug" => "example-app", "v" => 7})
    reindex()
    assert [%{version: 7}] = display()

    publish(%{"type" => "delist", "family" => 2, "slug" => "example-app"})
    reindex()
    assert display() == []

    publish(%{"type" => "listing", "family" => 2, "slug" => "example-app", "v" => 8})
    reindex()
    assert [%{version: 8}] = display()

    publish(%{"type" => "delist", "family" => 2, "slug" => "example-app"})
    reindex()
    assert display() == []
  end

  # Two listings can wear the same version and one app can be re-listed at a
  # new one: `{pk, slug}` is the row's identity, `v` is only ever a label
  # riding on it, so neither case collides.
  test "a newer version replaces its row, and shared versions do not merge rows" do
    publish(%{"type" => "listing", "family" => 2, "slug" => "twin-app", "v" => 1})
    publish(%{"type" => "listing", "family" => 2, "slug" => "twin-app", "v" => 2})
    publish(%{"type" => "listing", "family" => 2, "slug" => "twin-sibling", "v" => 2})
    reindex()

    pk = Preferences.get(:identity)

    # Re-listing replaces: exactly one row for the key, carrying the newest `v`.
    assert [{_key, %{version: 2}}] = :ets.lookup(:listings, {pk, "twin-app"})

    # Same version, different slugs: two rows, neither absorbed into the other.
    rows =
      for %{slug: slug} = row <- display(),
          slug in ["twin-app", "twin-sibling"],
          do: {slug, row.version}

    assert Enum.sort(rows) == [{"twin-app", 2}, {"twin-sibling", 2}]

    for slug <- ["twin-app", "twin-sibling"] do
      publish(%{"type" => "delist", "family" => 2, "slug" => slug})
    end

    reindex()
    assert display() == []
  end
end
