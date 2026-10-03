defmodule CatenaryWeb.AppPlaygroundTest do
  use ExUnit.Case, async: false

  alias Catenary.{Apps, Preferences}
  alias Catenary.Live.AppPlayground

  @slug "playground"

  setup do
    clump_id = Preferences.get(:clump_id)
    identity = Preferences.get(:identity)
    facet_id = Preferences.get(:facet_id)
    log_id = Apps.app_log_id(identity, @slug, facet_id)

    on_exit(fn ->
      Baobab.purge(Catenary.id_for_key(identity), log_id: log_id, clump_id: clump_id)
    end)

    %{clump_id: clump_id, identity: identity, facet_id: facet_id, log_id: log_id}
  end

  defp playground_socket(ctx) do
    AppPlayground.update(
      %{
        clump_id: ctx.clump_id,
        identity: ctx.identity,
        facet_id: ctx.facet_id,
        source: ""
      },
      %Phoenix.LiveView.Socket{}
    )
    |> elem(1)
  end

  test "a draft publishes into its own playground channel", ctx do
    socket = playground_socket(ctx)

    entry =
      %{"type" => "note", "text" => "from the draft"}
      |> CBOR.encode()
      |> Base.encode64()

    assert {:reply, %{"ok" => true, "seq" => seq}, _socket} =
             AppPlayground.handle_event("app-publish", %{"entry" => entry}, socket)

    assert seq > 0

    # The left rail browses this very channel, and only the parent can
    # reach it: a landing publish says so with a message up.
    assert_received :playground_channel_bump

    author = Baobab.Identity.as_base62(ctx.identity)
    assert Baobab.max_seqnum(author, log_id: ctx.log_id, clump_id: ctx.clump_id) >= 1
  end

  test "a publish refused says nothing — there is no entry to reread for", ctx do
    socket = playground_socket(ctx)

    assert {:reply, %{"ok" => false, "error" => "bad_args"}, _socket} =
             AppPlayground.handle_event("app-publish", %{}, socket)

    refute_received :playground_channel_bump
  end

  test "the component will not answer a publish without the facet it writes on" do
    facet_id = Preferences.get(:facet_id)

    # `update/2` pattern-matches the facet in, so a parent that forgets the
    # assign fails loudly instead of publishing somewhere unjudged.
    assigns =
      %{
        clump_id: Preferences.get(:clump_id),
        identity: Preferences.get(:identity),
        facet_id: facet_id,
        source: ""
      }
      |> Map.drop([:facet_id])

    assert_raise FunctionClauseError, fn ->
      AppPlayground.update(assigns, %Phoenix.LiveView.Socket{})
    end
  end

  # The fixture the picker points the run at moves only whose data an
  # unnamed read answers as. The key that publishes — and the channel the
  # publish lands on — stay this identity's, which is the scope §6 keeps.
  test "a fixture pick moves the default reader, never the publisher", ctx do
    fixture_key = String.duplicate("1", 43)

    socket =
      AppPlayground.update(
        %{
          clump_id: ctx.clump_id,
          identity: ctx.identity,
          facet_id: ctx.facet_id,
          source: "",
          fixture: {:sample, fixture_key}
        },
        %Phoenix.LiveView.Socket{}
      )
      |> elem(1)

    assert socket.assigns.app.author == fixture_key
    assert socket.assigns.app.pk == ctx.identity
    assert socket.assigns.scope.identity == ctx.identity
  end

  test "without a pick the run's reads default to the app's own key", ctx do
    socket = playground_socket(ctx)

    refute Map.has_key?(socket.assigns.app, :author)
  end

  test "a publish still lands on this identity's channel while pointed at a fixture", ctx do
    socket =
      AppPlayground.update(
        %{
          clump_id: ctx.clump_id,
          identity: ctx.identity,
          facet_id: ctx.facet_id,
          source: "",
          fixture: {:sample, String.duplicate("1", 43)}
        },
        %Phoenix.LiveView.Socket{}
      )
      |> elem(1)

    entry =
      %{"type" => "note", "text" => "while pointed elsewhere"}
      |> CBOR.encode()
      |> Base.encode64()

    assert {:reply, %{"ok" => true, "seq" => seq}, _socket} =
             AppPlayground.handle_event("app-publish", %{"entry" => entry}, socket)

    assert seq > 0

    author = Baobab.Identity.as_base62(ctx.identity)
    assert Baobab.max_seqnum(author, log_id: ctx.log_id, clump_id: ctx.clump_id) >= 1
  end
end
