defmodule CatenaryWeb.ImportControllerTest do
  use CatenaryWeb.ConnCase, async: false

  @sk BaseX.Base62.encode(:crypto.strong_rand_bytes(32))

  defp export_json(name) do
    Jason.encode!(%{
      "application" => "catenary",
      "identity" => name,
      "key_encoding" => "base62",
      "key_type" => "ed25519",
      "public_key" => "public",
      "secret_key" => @sk
    })
  end

  defp upload(body) do
    path = Path.join(System.tmp_dir!(), "catenary-import-test-#{System.unique_integer()}.json")
    File.write!(path, body)
    %Plug.Upload{path: path, filename: "identity.json"}
  end

  defp conn_with_flash, do: build_conn() |> Plug.Conn.assign(:flash, %{})

  test "imports a valid exported identity file" do
    conn =
      conn_with_flash()
      |> CatenaryWeb.ImportController.create(%{
        "identity_file" => upload(export_json("test-import-alice"))
      })

    assert conn.status == 302
    names = Baobab.Identity.list() |> Enum.map(fn {n, _k} -> n end)
    assert "test-import-alice" in names
    assert is_binary(Baobab.Identity.key("test-import-alice", :secret))
    Baobab.Identity.drop("test-import-alice")
  end

  test "auto-renames on a name collision" do
    existing = "test-import-bob-#{System.unique_integer()}"
    pk = Baobab.Identity.create(existing, :crypto.strong_rand_bytes(32))
    assert is_binary(pk)

    conn =
      conn_with_flash()
      |> CatenaryWeb.ImportController.create(%{"identity_file" => upload(export_json(existing))})

    assert conn.status == 302
    names = Baobab.Identity.list() |> Enum.map(fn {n, _k} -> n end)
    assert (existing <> "-1") in names
    # the pre-existing identity's keys must be untouched
    assert Baobab.Identity.key(existing, :secret) != BaseX.Base62.decode(@sk)
    Baobab.Identity.drop(existing)
    Baobab.Identity.drop(existing <> "-1")
  end

  test "fails when the keys already exist locally" do
    existing = "test-import-dup-#{System.unique_integer()}"
    sk = :crypto.strong_rand_bytes(32)
    pk = Baobab.Identity.create(existing, sk)
    assert is_binary(pk)

    exported =
      Jason.encode!(%{
        "application" => "catenary",
        "identity" => existing,
        "key_encoding" => "base62",
        "key_type" => "ed25519",
        "public_key" => pk,
        "secret_key" => BaseX.Base62.encode(sk)
      })

    conn =
      conn_with_flash()
      |> CatenaryWeb.ImportController.create(%{"identity_file" => upload(exported)})

    assert conn.status == 302
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "already exist here as identity"
    # nothing new was created
    names = Baobab.Identity.list() |> Enum.map(fn {n, _k} -> n end)
    refute (existing <> "-1") in names
    Baobab.Identity.drop(existing)
  end

  test "rejects an unrecognized file" do
    conn =
      conn_with_flash()
      |> CatenaryWeb.ImportController.create(%{"identity_file" => upload("{\"nope\": true}")})

    assert conn.status == 302
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Import failed"
  end
end
