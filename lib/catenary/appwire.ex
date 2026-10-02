defmodule Catenary.AppWire do
  @moduledoc """
  The wire format between a running app and the host.

  Everything crossing this boundary is CBOR wrapped in base64. LiveView
  carries JSON, and neither raw payload bytes nor arbitrary terms survive a
  round trip through it, so a request arrives as `base64(CBOR.encode(args))`
  and a reply leaves as a JSON map holding `data`, itself
  `base64(CBOR.encode(value))`, or a plain `error` string.

  Decoding lives here rather than inside `Catenary.AppHost` so the host keeps
  an Elixir-shaped contract and stays testable without a transport. Nothing
  in `args` is trusted: it is CBOR built by code the host does not control,
  so a malformed or partial message has to become an answer rather than a
  crash on the LiveView process.
  """

  alias Catenary.AppHost

  @type reply :: %{optional(String.t()) => term}

  @doc """
  Run one operation named by `op` over base64-wrapped CBOR `args`.

  Always returns a map that can go straight on the wire.
  """
  @spec request(AppHost.app(), term, term) :: reply
  def request(app, op, args) do
    with {:ok, decoded} <- decode_args(op, args),
         {:ok, value} <- AppHost.handle(app, op, decoded) do
      %{"ok" => true, "data" => value |> CBOR.encode() |> Base.encode64()}
    else
      {:error, reason} -> %{"ok" => false, "error" => message(reason)}
    end
  end

  @doc """
  Wrap Elixir arguments the way a worker would, for callers that already
  hold them as terms rather than as bytes.
  """
  @spec encode_args(map) :: String.t()
  def encode_args(args) when is_map(args), do: args |> CBOR.encode() |> Base.encode64()

  @doc """
  Unwrap `data` from a reply, for callers that want the term back.
  """
  @spec decode_data(reply) :: {:ok, term} | {:error, atom}
  def decode_data(%{"ok" => true, "data" => data}) do
    case Base.decode64(data) do
      {:ok, bin} ->
        case CBOR.decode(bin) do
          {:ok, value, ""} -> {:ok, value}
          _ -> {:error, :bad_reply}
        end

      :error ->
        {:error, :bad_reply}
    end
  end

  def decode_data(_reply), do: {:error, :bad_reply}

  defp decode_args(op, args) when is_binary(op) and is_binary(args) do
    with {:ok, encoded} <- Base.decode64(args),
         {:ok, value} <- cbor(encoded),
         :ok <- ensure_map(value) do
      {:ok, value}
    else
      {:error, reason} -> {:error, reason}
      :error -> {:error, :bad_args}
    end
  end

  defp decode_args(_op, _args), do: {:error, :bad_args}

  # Trailing bytes mean the sender did not produce one well-formed value,
  # so the request as a whole is suspect rather than merely truncated.
  defp cbor(binary) do
    case CBOR.decode(binary) do
      {:ok, value, ""} -> {:ok, value}
      {:ok, _value, _rest} -> {:error, :trailing_bytes}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_map(value) when is_map(value), do: :ok
  defp ensure_map(_), do: :error

  defp message(reason) when is_binary(reason), do: reason
  defp message(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp message(reason), do: inspect(reason)
end
