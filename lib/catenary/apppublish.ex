defmodule Catenary.AppPublish do
  @moduledoc """
  The write path for an app's data channel: what a `publish` effect becomes
  once it reaches the server (§6).

  Where an entry lands is never the module's decision. The scope — which app
  is running, which identity is signed in, which facet this device writes
  on — comes from the LiveView's assigns, so the target is
  `Apps.app_log_id(pk, slug, facet)`: the channel the running app's own
  `(pk, slug)` derives, checked with `Apps.data_channel?/1` so a base that
  happened to fold onto a reserved kind sub-id (§7 risk 2) is refused rather
  than handed the manifest log. The signature is the current identity's, and
  an identity that is not the publisher's is refused outright — an app open
  in the viewer under somebody else's key has no key here that could sign an
  entry readers would accept against this channel (§6, self-certifying
  namespace).

  Two fields are stamped rather than taken: `v` and `app`. A reader
  recomputes the channel base from the `app` string and the *signed* author,
  so it is built here from the same `pk` and `slug` the log was derived from
  rather than trusted out of CBOR the module wrote. `published` is stamped
  too — this host's clock at append, the same stamp every other entry type
  carries — because it is what lets a reader order a channel across device
  facets, where per-log sequence numbers alone say nothing about time.

  An entry is bounded before it is decoded (§7 risk 10) and has to carry a
  `type`, so what lands is a typed, sized data entry — not an artifact (the
  human-mediated publish path owns that size policy) and not an unlabelled
  blob a reader would have to guess about.

  The reply is the wire shape the loop already reads for a `want`:
  `%{"ok" => true, "seq" => n}` when the entry landed, `%{"ok" => false,
  "error" => reason}` when it did not. A publish carries no `ref`, so there
  is no message to hand back to the module and the loop turns a refusal into
  a strike.
  """

  alias Catenary.Apps

  # A data entry, not an artifact: the effect path is how a running app
  # appends to its own channel, and 64 KiB of CBOR is far past any move,
  # poll or note while staying a message LiveView can carry and a peer can
  # fetch in one piece. The cap is applied to the wire string before the
  # base64 is decoded and to the bytes before CBOR is, so neither decoder
  # ever sees more than this.
  @max_entry_bytes 64 * 1024
  @max_wire_bytes div(@max_entry_bytes * 4, 3) + 4

  @type scope :: %{
          app: Catenary.AppHost.app(),
          identity: binary,
          facet_id: 0..255
        }
  @type reply :: %{required(String.t()) => term}

  @doc """
  Append `entry` — `base64(CBOR(map))`, exactly as the worker sent it — to
  the data channel of the app in `scope`.

  Always returns a map that can go straight on the wire.
  """
  @spec publish(scope, term) :: reply
  def publish(
        %{
          app: %{clump_id: clump_id, pk: pk, slug: slug},
          identity: identity,
          facet_id: facet_id
        },
        entry
      )
      when is_binary(clump_id) and is_binary(pk) and is_binary(slug) and is_binary(identity) and
             is_integer(facet_id) and facet_id in 0..255 and is_binary(entry) do
    with {:ok, id} <- signer(identity, pk),
         {:ok, log_id} <- channel(pk, slug, facet_id),
         {:ok, decoded} <- entry_map(entry),
         :ok <- typed(decoded),
         {:ok, seq} <- append(decoded, pk, slug, log_id, id, clump_id) do
      %{"ok" => true, "seq" => seq}
    else
      {:error, reason} -> refused(reason)
    end
  end

  def publish(_scope, _entry), do: refused(:bad_args)

  # The key that signs, and the check that it is the publisher's. `pk` names
  # the app that is running; `identity` is the one signed in on this device.
  # They have to be the same key, or the entry would be signed by an author
  # whose own derivation is some other channel and no reader would accept it
  # where it landed.
  defp signer(identity, pk) do
    with {:ok, me} <- base62(identity),
         {:ok, publisher} <- base62(pk),
         true <- me == publisher do
      case Catenary.id_for_key(me) do
        {:error, _} -> {:error, :no_identity}
        id -> {:ok, id}
      end
    else
      false -> {:error, :not_the_publisher}
      {:error, reason} -> {:error, reason}
    end
  end

  defp base62(key) do
    case Baobab.Identity.as_base62(key) do
      {:error, _} -> {:error, :bad_args}
      base62 -> {:ok, base62}
    end
  end

  # The target log, derived rather than named: a slug that is not a slug
  # could not have been derived into anything, and a base that is not a data
  # channel is the kind-base collision §7 ranks — refused either way.
  defp channel(pk, slug, facet_id) do
    with {:ok, _slug} <- Apps.validate_slug(slug) do
      log_id = Apps.app_log_id(pk, slug, facet_id)

      if Apps.data_channel?(log_id),
        do: {:ok, log_id},
        else: {:error, :not_a_data_channel}
    end
  end

  # Bytes in, a map out, with every cap applied on the way: the wire string
  # before base64, the decoded bytes before CBOR, and the CBOR consumed in
  # full so a second value trailing the first is a malformed message rather
  # than half of a well-formed one.
  defp entry_map(entry) when byte_size(entry) <= @max_wire_bytes do
    case Base.decode64(entry) do
      {:ok, binary} ->
        if byte_size(binary) <= @max_entry_bytes, do: cbor_map(binary), else: too_large()

      :error ->
        {:error, :bad_args}
    end
  end

  defp entry_map(_entry), do: too_large()

  defp too_large, do: {:error, :entry_too_large}

  defp cbor_map(binary) do
    case CBOR.decode(binary) do
      {:ok, value, ""} when is_map(value) -> {:ok, value}
      {:ok, _value, ""} -> {:error, :entry_not_a_map}
      {:ok, _value, _rest} -> {:error, :trailing_bytes}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :bad_args}
  end

  # §6's shape: every published entry says what kind of thing it is. A module
  # that left it out, or sent something that is not text, is refused before
  # it lands rather than after a reader has had to guess.
  defp typed(%{"type" => type}) when is_binary(type), do: :ok
  defp typed(_entry), do: {:error, :untyped_entry}

  defp append(entry, pk, slug, log_id, id, clump_id) do
    payload =
      entry
      |> Map.put("v", 1)
      |> Map.put("app", pk <> "/" <> slug)
      |> Map.put("published", DateTime.utc_now() |> DateTime.to_string())
      |> CBOR.encode()

    %Baobab.Entry{seqnum: seq} =
      Baobab.append_log(payload, id, log_id: log_id, clump_id: clump_id)

    {:ok, seq}
  rescue
    # The store answers failures by raising, and a publish that could not be
    # written is a refusal the module has to be told about, not a reason to
    # take the LiveView process down with it.
    _ -> {:error, :append_failed}
  end

  defp refused(reason), do: %{"ok" => false, "error" => message(reason)}

  defp message(reason) when is_binary(reason), do: reason
  defp message(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp message(reason), do: inspect(reason)
end
