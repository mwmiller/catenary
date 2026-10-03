defmodule CatenaryWeb.AppController do
  use CatenaryWeb, :controller

  alias Catenary.{Apps, Preferences}

  # The bytes a viewer's pane fetches. The listing that led to a slug is
  # discovery; what is served is the release resolved straight out of the
  # store — newest manifest first, then the artifact that hashes to what
  # that manifest names — so the route can only hand out bytes some
  # manifest vouches for, and a slug nobody has released is a 404 rather
  # than a guess.
  def module(conn, %{"pk" => pk, "slug" => slug}) do
    case Apps.release(Preferences.get(:clump_id), pk, slug) do
      {:ok, %{bytes: bytes}} ->
        conn
        |> put_resp_content_type("application/wasm", nil)
        |> send_resp(:ok, bytes)

      {:error, reason} ->
        send_resp(conn, :not_found, "no release: #{reason}")
    end
  end
end
