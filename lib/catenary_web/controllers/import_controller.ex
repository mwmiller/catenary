defmodule CatenaryWeb.ImportController do
  @moduledoc """
  Import a previously exported identity JSON file.

  Expects the format produced by `CatenaryWeb.ExportController`. If the
  identity name already exists locally it is auto-renamed (`name`,
  `name-1`, `name-2`, ...) so that an import can never silently
  overwrite an extant identity's keys.
  """
  use CatenaryWeb, :controller

  def create(conn, %{"identity_file" => %Plug.Upload{} = upload} = _params) do
    case import_file(upload.path) do
      {:ok, name} ->
        respond(conn, :ok, "Imported identity as #{name}")

      {:error, reason} ->
        respond(conn, :error, "Import failed: #{reason}")
    end
  end

  def create(conn, _params) do
    respond(conn, :error, "Import failed: no identity file provided")
  end

  # We deliberately render the outcome as its own small page rather than a
  # flash: the form is a plain multipart POST, and the result — especially a
  # failure and why it happened — deserves to stay on screen until the
  # reader is done with it. The upload replaced the current page, so there
  # is nothing to return to but the app itself.
  defp respond(conn, :ok, message) do
    conn
    |> put_root_layout(false)
    |> html(page(message))
  end

  defp respond(conn, :error, message) do
    conn
    |> put_status(422)
    |> put_root_layout(false)
    |> html(page(message))
  end

  defp page(message) do
    safe = message |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Catenary — identity import</title>
      </head>
      <body style="margin:0;font-family:ui-sans-serif,system-ui,sans-serif;background:#0f172a;display:flex;align-items:center;justify-content:center;min-height:100vh;">
        <div style="max-width:28rem;padding:2rem;text-align:center;">
          <p style="margin:0 0 1.5rem;color:#e2e8f0;font-size:0.95rem;line-height:1.5;">#{safe}</p>
          <a href="/" style="color:#fbbf24;font-size:0.9rem;">return to catenary</a>
        </div>
      </body>
    </html>
    """
  end

  defp import_file(path) do
    with {:ok, body} <- File.read(path),
         {:ok, data} <- Jason.decode(body),
         :ok <- validate(data),
         {:ok, name} <- import_identity(data) do
      {:ok, name}
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      _ -> {:error, "invalid identity file"}
    end
  end

  defp validate(%{
         "application" => "catenary",
         "key_type" => "ed25519",
         "key_encoding" => "base62",
         "identity" => identity,
         "secret_key" => secret_key
       })
       when is_binary(identity) and is_binary(secret_key) do
    # A 32-byte key base62-encodes to 42 or 43 characters
    # (42 when the first byte is zero)
    if String.length(secret_key) in 42..43 do
      :ok
    else
      {:error, "secret key must be 42-43 base62 characters"}
    end
  end

  defp validate(_), do: {:error, "unrecognized identity file format"}

  # Returns an unused name derived from the exported identity name
  defp available_name(base, taken) do
    if MapSet.member?(taken, base) do
      available_suffix(base, 1, taken)
    else
      base
    end
  end

  defp available_suffix(base, n, taken) do
    candidate = base <> "-" <> Integer.to_string(n)

    if MapSet.member?(taken, candidate) do
      available_suffix(base, n + 1, taken)
    else
      candidate
    end
  end

  defp import_identity(%{"identity" => name, "secret_key" => sk}) do
    with {:ok, raw_sk} <- decode_secret_key(sk),
         pk = Ed25519.derive_public_key(raw_sk),
         pk62 = BaseX.Base62.encode(pk),
         :ok <- check_key_not_present(pk62) do
      taken =
        Baobab.Identity.list()
        |> Enum.map(fn {n, _k} -> n end)
        |> MapSet.new()

      chosen = available_name(name, taken)

      case Baobab.Identity.create(chosen, raw_sk) do
        {:error, reason} -> {:error, reason}
        _pk -> {:ok, chosen}
      end
    end
  end

  # Refuse to import keys which already exist locally; auto-rename
  # is only for name collisions with *different* keys.
  defp check_key_not_present(pk62) do
    case Enum.find(Baobab.Identity.list(), fn {_n, k} -> k == pk62 end) do
      {name, _} -> {:error, "these keys already exist here as identity #{name}"}
      nil -> :ok
    end
  end

  # Decode to raw bytes, zero-padding on the left to a full 32 bytes
  # (a leading zero byte is stripped by the base62 encoding)
  defp decode_secret_key(sk) do
    case BaseX.Base62.decode(sk) do
      raw when byte_size(raw) <= 32 ->
        pad = 32 - byte_size(raw)
        {:ok, <<0::size(pad * 8), raw::binary>>}

      _ ->
        {:error, "improper base62 secret key"}
    end
  rescue
    _ -> {:error, "improper base62 secret key"}
  end
end
