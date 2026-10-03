defmodule CatenaryWeb.Live.ChannelListTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Catenary.{Apps, Preferences}
  alias Catenary.Live.ChannelList

  @slug "channellist-test"

  setup do
    clump_id = Preferences.get(:clump_id)
    facet_id = Preferences.get(:facet_id)
    pk = Preferences.get(:identity)

    purge(pk, clump_id)
    on_exit(fn -> purge(pk, clump_id) end)

    %{clump_id: clump_id, facet_id: facet_id, pk: pk}
  end

  defp purge(pk, clump_id) do
    for facet <- 0..7 do
      Baobab.purge(pk,
        log_id: Apps.app_log_id(pk, @slug, facet),
        clump_id: clump_id
      )
    end
  end

  defp publish(ctx, data, facet \\ 0) do
    log_id = Apps.app_log_id(ctx.pk, @slug, facet)

    Baobab.append_log(
      CBOR.encode(Map.put_new(data, "published", DateTime.utc_now() |> DateTime.to_string())),
      Catenary.id_for_key(ctx.pk),
      log_id: log_id,
      clump_id: ctx.clump_id
    )
  end

  defp assigns(ctx, overrides \\ %{}) do
    Map.merge(
      %{
        id: :channel_list_test,
        clump_id: ctx.clump_id,
        pk: ctx.pk,
        slug: @slug,
        channel_bump: 0,
        index_version: 0
      },
      overrides
    )
  end

  defp render_list(ctx, overrides \\ %{}) do
    render_component(ChannelList, assigns(ctx, overrides))
  end

  test "entries come back newest published first, each one a view link", ctx do
    publish(ctx, %{
      "type" => "note",
      "text" => "the older note",
      "published" => "2026-10-01 00:00:00 UTC"
    })

    publish(ctx, %{
      "type" => "note",
      "text" => "the newer note",
      "published" => "2026-10-02 00:00:00 UTC"
    })

    html = render_list(ctx)

    assert html =~ "the older note"
    assert html =~ "the newer note"
    assert html =~ "note"
    assert html =~ ~s(phx-click="view-entry")

    newer_at = :binary.match(html, "the newer note") |> elem(0)
    older_at = :binary.match(html, "the older note") |> elem(0)
    assert newer_at < older_at
  end

  test "a channel nobody has written to says so", ctx do
    assert render_list(ctx) =~ "Nothing published here yet."
  end

  test "rows move only when a counter says the store might have", ctx do
    publish(ctx, %{"type" => "note", "text" => "first"})

    {:ok, socket} =
      ChannelList.update(assigns(ctx), %Phoenix.LiveView.Socket{})

    assert Enum.map(socket.assigns.rows, & &1.summary) == ["first"]

    # The parent repainting for its own reasons — a keystroke, a trace
    # line — is not a reason to read the store: same counters, same rows.
    publish(ctx, %{"type" => "note", "text" => "second"})

    {:ok, same} = ChannelList.update(assigns(ctx), socket)
    assert Enum.map(same.assigns.rows, & &1.summary) == ["first"]

    # The publish counter moving is: the answer may have changed.
    {:ok, bumped} =
      ChannelList.update(assigns(ctx, %{channel_bump: 1}), socket)

    assert bumped.assigns.rows |> Enum.map(& &1.summary) |> Enum.sort() == ["first", "second"]
  end

  test "a summary is one line of the entry's own words", ctx do
    publish(ctx, %{"type" => "note", "text" => "first line\nsecond line"})

    assert render_list(ctx) =~ "first line"
    refute render_list(ctx) =~ "second line"
  end
end
