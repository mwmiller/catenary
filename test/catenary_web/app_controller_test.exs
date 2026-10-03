defmodule CatenaryWeb.AppControllerTest do
  use CatenaryWeb.ConnCase, async: false

  alias Catenary.{LogWriter, Preferences}

  # The route a viewer's pane fetches (§9.7 phase 2b). It serves bytes
  # resolved from the store, so the test publishes a release the way the
  # panel does and then asks for it over HTTP.
  @slug "route-app"

  @source ~S|on init:
  print(1)
|

  defp socket do
    %{
      assigns: %{
        identity: Preferences.get(:identity),
        facet_id: Preferences.get(:facet_id),
        clump_id: Preferences.get(:clump_id)
      }
    }
  end

  setup do
    identity = Preferences.get(:identity)

    {:ok, result} =
      LogWriter.publish_app(
        %{"slug" => @slug, "title" => "Route", "source" => @source},
        socket()
      )

    on_exit(fn ->
      %{"type" => "delist", "family" => Catenary.Apps.family(), "slug" => @slug}
      |> Map.put("published", DateTime.utc_now() |> DateTime.to_string())
      |> CBOR.encode()
      |> Baobab.append_log(Catenary.id_for_key(Preferences.get(:identity)),
        log_id: QuaggaDef.facet_log(Catenary.Apps.control_log(), Preferences.get(:facet_id)),
        clump_id: Preferences.get(:clump_id)
      )

      GenServer.call(:listings, :update)
    end)

    %{pk: identity, result: result}
  end

  test "the module route serves the release's bytes", %{conn: conn, pk: pk, result: result} do
    conn = get(conn, "/apps/#{pk}/#{@slug}/module")

    assert conn.status == 200
    assert response_content_type(conn, :wasm) == "application/wasm"
    assert :crypto.hash(:sha256, conn.resp_body) == result.code
    assert byte_size(conn.resp_body) == result.bytes
  end

  test "a slug nobody released is a 404", %{conn: conn, pk: pk} do
    conn = get(conn, "/apps/#{pk}/route-never-released/module")

    assert conn.status == 404
    assert conn.resp_body =~ "not_released"
  end

  test "another author's unpublished slug is a 404", %{conn: conn} do
    conn = get(conn, "/apps/#{String.duplicate("1", 43)}/#{@slug}/module")

    assert conn.status == 404
    assert conn.resp_body =~ "not_released"
  end
end
