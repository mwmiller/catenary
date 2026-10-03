defmodule CatenaryWeb.AppViewerTest do
  use CatenaryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Catenary.{AppHost, AppKV, Apps, AppWire, Preferences}
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

    %{app: app, clump_id: clump_id, identity: identity}
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
    # No module is configured for this slug, so the hook starts idle.
    refute html =~ "data-wasm-src"
    assert html =~ "No module loaded."
    assert html =~ "viewer-app"
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

  test "a slug with a module configured points the hook at it" do
    previous = Application.get_env(:catenary, :app_wasm)
    Application.put_env(:catenary, :app_wasm, %{"viewer-app" => "/assets/fixture.wasm"})

    on_exit(fn ->
      if previous do
        Application.put_env(:catenary, :app_wasm, previous)
      else
        Application.delete_env(:catenary, :app_wasm)
      end
    end)

    announce("viewer-app")

    {:ok, view, _html} = live(build_conn(), "/")
    view |> element("button[title=Listings]") |> render_click()
    view |> element("button[phx-value-slug=\"viewer-app\"]") |> render_click()

    html = render(view)
    assert html =~ ~s(data-wasm-src="/assets/fixture.wasm")
    assert html =~ ~s(data-worker-src="/assets/app_worker.js")
    {pos, _} = :binary.match(html, "app-pane")
    pane = String.slice(html, pos, 400)
    assert pane =~ ~r/phx-target="\d+"/
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
end
