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
        conn
        |> put_flash(:info, "Imported identity as #{name}")
        |> redirect(to: "/")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Import failed: #{reason}")
        |> redirect(to: "/")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Import failed: no identity file provided")
    |> redirect(to: "/")
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
    cond do
      not MapSet.member?(taken, base) -> base
      true -> available_suffix(base, 1, taken)
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
         taken =
           Baobab.Identity.list()
           |> Enum.map(fn {n, _k} -> n end)
           |> MapSet.new(),
         chosen = available_name(name, taken),
         create_result = Baobab.Identity.create(chosen, raw_sk) do
      case create_result do
        {:error, reason} -> {:error, reason}
        _pk -> {:ok, chosen}
      end
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
