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

    author = Baobab.Identity.as_base62(ctx.identity)
    assert Baobab.max_seqnum(author, log_id: ctx.log_id, clump_id: ctx.clump_id) >= 1
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
end
