defmodule CatenaryWeb.AppViewerTest do
  use CatenaryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Catenary.{AppHost, AppKV, Apps, AppWire, LogWriter, Preferences}
  alias Catenary.Live.{AppViewer, ListingsExplorer}

  # A key that is not this device's, standing in for the publisher of an
  # app somebody else published.
  @foreign_pk String.duplicate("1", 43)

  setup do
    # Navigation writes view and entry straight back to the preference store,
    # and that store outlives the suite. Put both back so the next test opens
    # on the screen it always did.
    original = %{view: Preferences.get(:view), entry: Preferences.get(:entry)}
    on_exit(fn -> Enum.each(original, fn {k, v} -> Preferences.set(k, v) end) end)

    clump_id = Preferences.get(:clump_id)
    identity = Preferences.get(:identity)
    app = AppHost.app(clump_id, identity, "viewer-app")
    AppKV.clear(app)

    # A publish from any test here would be the next test's channel
    # contents — and the tests run in no fixed order — so the channel this
    # app derives is taken back before the first test and after every one.
    purge_channel(clump_id, identity, "viewer-app")
    on_exit(fn -> purge_channel(clump_id, identity, "viewer-app") end)

    %{app: app, clump_id: clump_id, identity: identity}
  end

  defp purge_channel(clump_id, identity, slug) do
    for facet <- 0..7 do
      Baobab.purge(Catenary.id_for_key(identity),
        log_id: Apps.app_log_id(identity, slug, facet),
        clump_id: clump_id
      )
    end
  end

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

  defp reindex, do: GenServer.call(:listings, :update)

  # The component's context as the parent passes it: the listing that was
  # opened, plus the two assigns a publish is judged against — who is signed
  # in and which facet this device writes on (§6).
  defp viewer_socket(ctx, slug) do
    AppViewer.update(
      %{
        clump_id: ctx.clump_id,
        pk: ctx.identity,
        slug: slug,
        identity: ctx.identity,
        facet_id: Preferences.get(:facet_id)
      },
      %Phoenix.LiveView.Socket{}
    )
    |> elem(1)
  end

  # The control log persists across runs, so whatever is announced here has
  # to be withdrawn again or the next test to render the explorer sees it.
  defp announce(slug) do
    publish(%{"type" => "listing", "family" => 2, "slug" => slug, "v" => 1})
    reindex()

    on_exit(fn ->
      publish(%{"type" => "delist", "family" => 2, "slug" => slug})
      reindex()
    end)
  end

  test "opening an announced listing lands in the app view", ctx do
    announce("viewer-app")

    {:ok, view, _html} = live(build_conn(), "/")
    view |> element("button[title=Listings]") |> render_click()

    assert has_element?(view, "button[phx-value-slug=\"viewer-app\"]")
    view |> element("button[phx-value-slug=\"viewer-app\"]") |> render_click()

    html = render(view)
    assert html =~ "phx-hook=\"AppRunner\""
    assert html =~ "phx-update=\"ignore\""
    assert html =~ ~s(data-worker-src="/assets/app_worker.js")
    # Named after the app so that a second app replaces the pane rather than
    # inheriting the first one's print log.
    assert html =~ "app-pane-#{ctx.identity}-viewer-app"
    # No release stands behind this slug, so the hook starts idle.
    refute html =~ "data-wasm-src"
    assert html =~ "No module loaded."
    assert html =~ "viewer-app"
    # The pane talks back to its own component.
    {pos, _} = :binary.match(html, "app-pane")
    pane = String.slice(html, pos, 400)
    assert pane =~ ~r/phx-target="\d+"/
  end

  test "a saved app entry with no listing behind it still renders" do
    Preferences.set(:view, :app)
    Preferences.set(:entry, :all)

    {:ok, _view, html} = live(build_conn(), "/")
    assert html =~ "No app open."
  end

  test "only a listing the control log announced can be opened" do
    socket = %Phoenix.LiveView.Socket{}

    ListingsExplorer.handle_event(
      "open-app",
      %{"pk" => "nobody", "slug" => "ghost-app"},
      socket
    )

    refute_received %{view: :app, entry: {:app, _}}

    announce("viewer-app")
    pk = Preferences.get(:identity)

    ListingsExplorer.handle_event("open-app", %{"pk" => pk, "slug" => "viewer-app"}, socket)

    assert_received %{view: :app, entry: {:app, {^pk, "viewer-app"}}}
  end

  # A release replaces any other answer for a slug: a manifest behind it
  # has the pane pointed at the route that serves those bytes (§9.7 phase
  # 2b). There is no dev-config fallback to fall back to — a slug with no
  # manifest is left with the pane's own words.
  test "a released slug points its pane at the release route", ctx do
    announce("released-app")

    {:ok, _result} =
      LogWriter.publish_app(
        %{
          "slug" => "released-app",
          "title" => "Released",
          "source" => ~S|on init:
  print(1)
|
        },
        %{
          assigns: %{
            identity: Preferences.get(:identity),
            facet_id: Preferences.get(:facet_id),
            clump_id: Preferences.get(:clump_id)
          }
        }
      )

    {:ok, view, _html} = live(build_conn(), "/")
    view |> element("button[title=Listings]") |> render_click()
    view |> element("button[phx-value-slug=\"released-app\"]") |> render_click()

    html = render(view)
    assert html =~ ~s(data-wasm-src="/apps/#{ctx.identity}/released-app/module")
  end

  test "app-want is answered against the component's own context", ctx do
    socket = viewer_socket(ctx, "viewer-app")

    {:reply, reply, _socket} =
      AppViewer.handle_event(
        "app-want",
        %{"op" => "storage_set", "args" => AppWire.encode_args(%{key: "k", value: 7})},
        socket
      )

    assert {:ok, "stored"} = AppWire.decode_data(reply)

    {:reply, reply, _socket} =
      AppViewer.handle_event(
        "app-want",
        %{"op" => "storage_get", "args" => AppWire.encode_args(%{key: "k"})},
        socket
      )

    assert {:ok, 7} = AppWire.decode_data(reply)

    # The context comes from the entry the parent navigated to, so a second
    # app opened through the same component sees an empty store of its own.
    other = viewer_socket(ctx, "other-app")

    {:reply, reply, _socket} =
      AppViewer.handle_event(
        "app-want",
        %{"op" => "storage_get", "args" => AppWire.encode_args(%{key: "k"})},
        other
      )

    assert reply == %{"ok" => false, "error" => "not_found"}
  end

  # The reply still goes back over the wire untouched, but the baseline
  # inside it is handed up to the parent, which is the one that polls the
  # log (§9.4).
  test "a watch reply hands the parent the baseline to poll from", ctx do
    socket = viewer_socket(ctx, "viewer-app")
    log_id = Apps.app_log_id(ctx.identity, "viewer-app", Preferences.get(:facet_id))

    {:reply, reply, _socket} =
      AppViewer.handle_event(
        "app-want",
        %{"op" => "watch", "args" => AppWire.encode_args(%{log_id: log_id})},
        socket
      )

    assert {:ok, %{"author" => author, "log_id" => ^log_id, "seq" => seq}} =
             AppWire.decode_data(reply)

    assert is_integer(seq)
    assert_received {:app_watch, ^author, ^log_id, ^seq}
  end

  test "a message missing part of the wire is answered, not raised on", ctx do
    socket = viewer_socket(ctx, "viewer-app")

    assert {:reply, %{"ok" => false, "error" => "bad_args"}, _socket} =
             AppViewer.handle_event("app-want", %{"op" => "storage_get"}, socket)

    assert {:reply, %{"ok" => false, "error" => "bad_args"}, _socket} =
             AppViewer.handle_event("app-want", %{"args" => AppWire.encode_args(%{})}, socket)
  end

  test "app-publish lands on the channel of the app that is open", ctx do
    socket = viewer_socket(ctx, "viewer-app")
    facet_id = Preferences.get(:facet_id)
    log_id = Apps.app_log_id(ctx.identity, "viewer-app", facet_id)

    on_exit(fn ->
      Baobab.purge(Catenary.id_for_key(ctx.identity), log_id: log_id, clump_id: ctx.clump_id)
    end)

    entry = %{"type" => "note", "text" => "from the viewer"} |> CBOR.encode() |> Base.encode64()

    assert {:reply, %{"ok" => true, "seq" => seq}, _socket} =
             AppViewer.handle_event("app-publish", %{"entry" => entry}, socket)

    assert seq > 0

    # The component answers a message missing its payload rather than
    # raising on it, the way `app-want` does.
    assert {:reply, %{"ok" => false, "error" => "bad_args"}, _socket} =
             AppViewer.handle_event("app-publish", %{}, socket)
  end

  test "somebody else's app running here cannot publish into its channel", ctx do
    socket =
      AppViewer.update(
        %{
          clump_id: ctx.clump_id,
          pk: @foreign_pk,
          slug: "viewer-app",
          identity: ctx.identity,
          facet_id: Preferences.get(:facet_id)
        },
        %Phoenix.LiveView.Socket{}
      )
      |> elem(1)

    entry = %{"type" => "note"} |> CBOR.encode() |> Base.encode64()

    assert {:reply, %{"ok" => false, "error" => "not_the_publisher"}, _socket} =
             AppViewer.handle_event("app-publish", %{"entry" => entry}, socket)
  end

  # The component as the parent renders it — the full assign set a render
  # of the view would pass, including the two counters the channel browser
  # memoises on. `aliases` is the state tuple `short_id/2` folds, which
  # the parent builds once at mount.
  defp render_viewer(ctx, slug) do
    render_component(AppViewer, %{
      id: :app,
      clump_id: ctx.clump_id,
      pk: ctx.identity,
      slug: slug,
      identity: ctx.identity,
      facet_id: Preferences.get(:facet_id),
      aliases: nil,
      index_version: 0,
      entry: {:app, {ctx.identity, slug}}
    })
  end

  # Entries in an app's channel, on the facet this device writes on — the
  # same store write a publish makes, without going through the pane. The
  # append is by the identity's *name*, which is what the store keys on,
  # and the setup fixture takes the channel back afterwards.
  defp channel_entry(ctx, slug, data) do
    log_id = Apps.app_log_id(ctx.identity, slug, Preferences.get(:facet_id))

    Baobab.append_log(
      CBOR.encode(Map.put_new(data, "published", DateTime.utc_now() |> DateTime.to_string())),
      Catenary.id_for_key(ctx.identity),
      log_id: log_id,
      clump_id: ctx.clump_id
    )
  end

  test "the viewer lists the open app's channel beneath its pane", ctx do
    channel_entry(ctx, "viewer-app", %{
      "type" => "note",
      "text" => "written to the channel while the pane runs"
    })

    html = render_viewer(ctx, "viewer-app")

    # The browser's own id, its heading, and the entry itself — each row a
    # link into the viewer, the way every entry elsewhere is.
    assert html =~ ~s(id="app_channel")
    assert html =~ "Channel"
    assert html =~ "written to the channel while the pane runs"
    assert html =~ ~s(phx-click="view-entry")
  end

  test "a quiet channel says so rather than drawing an empty list", ctx do
    html = render_viewer(ctx, "viewer-app")
    assert html =~ "Nothing published here yet."
  end

  test "a landing publish moves the counter the channel list rereads on", ctx do
    socket = viewer_socket(ctx, "viewer-app")
    entry = %{"type" => "note", "text" => "bump"} |> CBOR.encode() |> Base.encode64()

    assert {:reply, %{"ok" => true}, bumped} =
             AppViewer.handle_event("app-publish", %{"entry" => entry}, socket)

    assert bumped.assigns.channel_bump == socket.assigns.channel_bump + 1

    # A refusal moves nothing: there is no entry to show, so there is no
    # reason to read the store again. Judged from where the last landing
    # publish left the counter.
    assert {:reply, %{"ok" => false}, refused} =
             AppViewer.handle_event("app-publish", %{}, bumped)

    assert refused.assigns.channel_bump == bumped.assigns.channel_bump
  end
end
