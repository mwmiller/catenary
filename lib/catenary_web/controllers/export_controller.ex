defmodule CatenaryWeb.ExportController do
  use CatenaryWeb, :controller

  def create(conn, %{"whom" => whom} = _params) when is_binary(whom) do
    json_data =
      %{
        application: "catenary",
        identity: whom,
        key_encoding: "base62",
        key_type: "ed25519",
        public_key: Baobab.identity_key(whom, :public) |> BaseX.Base62.encode(),
        secret_key: Baobab.identity_key(whom, :secret) |> BaseX.Base62.encode()
      }
      |> Jason.encode!()

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("content-disposition", "attachment; filename=" <> quoted_filename(whom))
    |> put_root_layout(false)
    |> send_resp(200, json_data)
  end

  def quoted_filename(whom), do: (whom <> ".json") |> IO.inspect()
end
