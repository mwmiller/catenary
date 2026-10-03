defmodule Catenary.SampleAuthorTest do
  use ExUnit.Case, async: false

  alias Catenary.{AppHost, Preferences, SampleAuthor, SampleAuthorFixture}

  setup do
    clump_id = Preferences.get(:clump_id)
    facet_id = Preferences.get(:facet_id)

    # Each test begins from the store without the fixture — including what
    # an earlier run of the suite left standing — so "first use" means it.
    SampleAuthorFixture.purge()
    on_exit(fn -> SampleAuthorFixture.purge() end)

    %{clump_id: clump_id, facet_id: facet_id}
  end

  test "first use creates the identity and writes three posts and a profile", ctx do
    assert {:ok, pk} = SampleAuthor.ensure(ctx.clump_id, ctx.facet_id)
    assert byte_size(pk) == 43

    journal = QuaggaDef.facet_log(:journal, ctx.facet_id)
    about = QuaggaDef.facet_log(:about, ctx.facet_id)

    assert Baobab.max_seqnum(pk, log_id: journal, clump_id: ctx.clump_id) == 3
    assert Baobab.max_seqnum(pk, log_id: about, clump_id: ctx.clump_id) == 1
  end

  test "a second pick finds the same key and appends nothing", ctx do
    assert {:ok, pk} = SampleAuthor.ensure(ctx.clump_id, ctx.facet_id)
    assert {:ok, ^pk} = SampleAuthor.ensure(ctx.clump_id, ctx.facet_id)

    journal = QuaggaDef.facet_log(:journal, ctx.facet_id)
    about = QuaggaDef.facet_log(:about, ctx.facet_id)

    assert Baobab.max_seqnum(pk, log_id: journal, clump_id: ctx.clump_id) == 3
    assert Baobab.max_seqnum(pk, log_id: about, clump_id: ctx.clump_id) == 1
  end

  test "a run pointed at the fixture reads its timeline and profile", ctx do
    assert {:ok, pk} = SampleAuthor.ensure(ctx.clump_id, ctx.facet_id)

    app = AppHost.app(ctx.clump_id, "someone-else", "example-app", pk)

    assert {:ok, entries} = AppHost.handle(app, "timeline", %{})
    assert length(entries) == 3

    # Newest published first, which for these posts is also highest seq.
    assert [newest, _, oldest] = entries
    assert newest["seq"] == 3
    assert oldest["seq"] == 1
    assert Enum.all?(entries, &(&1["author"] == pk))
    assert newest["published"] > oldest["published"]

    assert {:ok, profile} = AppHost.handle(app, "profile", %{})
    assert profile["author"] == pk
    assert profile["about"]["name"] == "Sample Author"
  end

  test "a log emptied behind the fixture is refilled on the next pick", ctx do
    assert {:ok, pk} = SampleAuthor.ensure(ctx.clump_id, ctx.facet_id)

    journal = QuaggaDef.facet_log(:journal, ctx.facet_id)
    Baobab.purge(pk, log_id: journal, clump_id: ctx.clump_id)

    assert {:ok, ^pk} = SampleAuthor.ensure(ctx.clump_id, ctx.facet_id)
    assert Baobab.max_seqnum(pk, log_id: journal, clump_id: ctx.clump_id) == 3
  end
end
