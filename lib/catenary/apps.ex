defmodule Catenary.Apps do
  @moduledoc """
  Log layout, slug rules and identity derivation for user-published
  applications.

  Applications live in derived-log family `0x2` (`QuaggaDef.family_tag/1`).
  Two shapes of log exist inside it:

    * **kind logs** — three fixed sub-ids every author carries: the manifest,
      the artifact and the optional source entry. Fixed sub-ids give an index
      worker a static scan list; the values are reserved so a hash-derived
      channel base can never land on one (`kind_log?/1` is the publish-path
      check that makes the p ~= 3/2^48 collision harmless).

    * **data channels** — one per `(pk, slug)`, derived from
      `SHA-256(pk <> slug)` so any peer can recompute the base and fetch the
      channel without an announcement.

  Discovery of both rides the family's hand-allocated control log
  (`QuaggaDef.control_log(:app)`, 2777), reached through `control_log/0`
  and `listing_logs/0`.

  An app's full ID is `<base62_pk>/<slug>`: the signing key is the namespace,
  so two authors can both publish `example-app` without colliding.
  """

  @family QuaggaDef.family_tag(:app)
  @manifest QuaggaDef.derived_log_base(1, @family)
  @artifact QuaggaDef.derived_log_base(2, @family)
  @source QuaggaDef.derived_log_base(3, @family)
  @kind_logs [@manifest, @artifact, @source]

  # Strict ASCII only, and hashed byte-for-byte: no trimming, case folding or
  # Unicode canonicalization ever happens to a slug. Two clients that
  # normalized differently would derive different bases and never find each
  # other's app, so input is rejected rather than rewritten.
  @slug_max 64

  @typedoc "A base62-encoded Baobab public key, as held in `socket.assigns.identity`."
  @type pk :: binary
  @typedoc "An application slug: strict `[a-z0-9-]{1,64}`."
  @type slug :: binary
  @typedoc "A `<base62_pk>/<slug>` application ID."
  @type app_id :: binary
  @typedoc "A base log ID: facet bits stripped, family tag intact."
  @type base :: non_neg_integer

  @doc "The derived-log family tag for applications (`0x2`)."
  @spec family() :: 1..255
  def family, do: @family

  @doc "The manifest kind base: every author's own copy of their app manifests."
  @spec manifest_log() :: base
  def manifest_log, do: @manifest

  @doc "The artifact kind base: the compiled wasm bytes an entry pins."
  @spec artifact_log() :: base
  def artifact_log, do: @artifact

  @doc "The source kind base: optional auditable text, hash-linked from the manifest."
  @spec source_log() :: base
  def source_log, do: @source

  @doc """
  The three reserved kind sub-ids inside the app family.

  ## Examples

      iex> Catenary.Apps.kind_logs()
      [562949953421313, 562949953421314, 562949953421315]

  """
  @spec kind_logs() :: [base]
  def kind_logs, do: @kind_logs

  @doc "The hand-allocated control (discovery) log for the app family."
  @spec control_log() :: base
  def control_log, do: QuaggaDef.control_log(:app)

  @doc """
  The facet-expanded `log_id` list of the app family's control log — the
  static scan list for the `:listings` index worker.

  ## Examples

      iex> length(Catenary.Apps.listing_logs())
      256

  """
  @spec listing_logs() :: [non_neg_integer]
  def listing_logs, do: QuaggaDef.control_logs(:app)

  @doc """
  Whether a term is an acceptable application slug.

  Slugs are strict ASCII `[a-z0-9-]{1,64}` and are hashed byte-for-byte.

  ## Examples

      iex> Catenary.Apps.valid_slug?("example-app")
      true

      iex> Catenary.Apps.valid_slug?("Example-App")
      false

      iex> Catenary.Apps.valid_slug?("example-app ")
      false

      iex> Catenary.Apps.valid_slug?("-")
      true

      iex> Catenary.Apps.valid_slug?(String.duplicate("a", 65))
      false

      iex> Catenary.Apps.valid_slug?("example-app!")
      false

  """
  @spec valid_slug?(term) :: boolean
  def valid_slug?(slug) when is_binary(slug) and byte_size(slug) in 1..@slug_max do
    slug
    |> :binary.bin_to_list()
    |> Enum.all?(&(&1 in ?a..?z or &1 in ?0..?9 or &1 == ?-))
  end

  def valid_slug?(_), do: false

  @doc """
  The descriptive line a listing carries, when it carries one.

  The control log is written by anyone, so the field is only ever taken as
  text and never checked for length: how much of it a view shows is the
  view's business. An entry without one still lists.

  ## Examples

      iex> Catenary.Apps.description(%{"description" => "a tiny hello"})
      "a tiny hello"

      iex> Catenary.Apps.description(%{"description" => 7})
      nil

      iex> Catenary.Apps.description(%{"description" => ""})
      nil

      iex> Catenary.Apps.description(%{})
      nil

  """
  @spec description(map) :: binary | nil
  def description(%{"description" => text}) when is_binary(text) and text != "", do: text
  def description(_data), do: nil

  @doc """
  Validate a slug, returning it unchanged on success.

  ## Examples

      iex> Catenary.Apps.validate_slug("example-app")
      {:ok, "example-app"}

      iex> Catenary.Apps.validate_slug("Example-App")
      {:error, :invalid_slug}

      iex> Catenary.Apps.validate_slug(42)
      {:error, :invalid_slug}

  """
  @spec validate_slug(term) :: {:ok, slug} | {:error, :invalid_slug}
  def validate_slug(slug) do
    if valid_slug?(slug), do: {:ok, slug}, else: {:error, :invalid_slug}
  end

  @doc """
  The canonical `<base62_pk>/<slug>` ID for an application.

  The slug is validated, so a bad slug cannot be smuggled into an ID that
  later gets parsed back out.

  ## Examples

      iex> Catenary.Apps.app_id("ExampleAuthor1", "example-app")
      "ExampleAuthor1/example-app"

      iex> Catenary.Apps.app_id("ExampleAuthor1", "Example-App")
      {:error, :invalid_slug}

  """
  @spec app_id(pk, slug) :: app_id | {:error, :invalid_slug}
  def app_id(pk, slug) when is_binary(pk) do
    with {:ok, slug} <- validate_slug(slug) do
      pk <> "/" <> slug
    end
  end

  @doc """
  Split an `<base62_pk>/<slug>` ID back into its parts.

  Only the slug is validated here: the key half is whatever the signed
  author actually is, and callers comparing against it do so directly.

  ## Examples

      iex> Catenary.Apps.parse_app_id("ExampleAuthor1/example-app")
      {:ok, {"ExampleAuthor1", "example-app"}}

      iex> Catenary.Apps.parse_app_id("ExampleAuthor1/Example-App")
      {:error, :invalid_slug}

      iex> Catenary.Apps.parse_app_id("ExampleAuthor1")
      {:error, :bad_app_id}

      iex> Catenary.Apps.parse_app_id("/example-app")
      {:error, :bad_app_id}

  """
  @spec parse_app_id(term) :: {:ok, {pk, slug}} | {:error, :bad_app_id | :invalid_slug}
  def parse_app_id(id) when is_binary(id) do
    case String.split(id, "/", parts: 2) do
      [pk, slug] when pk != "" ->
        case validate_slug(slug) do
          {:ok, valid} -> {:ok, {pk, valid}}
          error -> error
        end

      _ ->
        {:error, :bad_app_id}
    end
  end

  def parse_app_id(_), do: {:error, :bad_app_id}

  @doc """
  The derived base log for an application's data channel.

  `SHA-256(pk <> slug)` is folded the same way the backgammon game base is:
  the first six bytes are read little-endian and handed to
  `QuaggaDef.derived_log_base/2`, which plants the app family tag in bits
  48..55. The base is therefore never a hand-allocated ID, and any peer can
  recompute it from nothing but the publisher's key and slug.

  ## Examples

      iex> Catenary.Apps.app_base(
      ...>   "ExampleAuthor1",
      ...>   "example-app"
      ...> )
      656499575700829

      iex> Catenary.Apps.app_base(
      ...>   "ExampleAuthor1",
      ...>   "other-app"
      ...> )
      643165031074013

      iex> QuaggaDef.family_for_block(
      ...>   Catenary.Apps.app_base("ExampleAuthor1", "example-app")
      ...> )
      :app

  """
  @spec app_base(pk, slug) :: base
  def app_base(pk, slug) when is_binary(pk) and is_binary(slug) do
    <<folded::unsigned-little-48, _rest::binary>> = :crypto.hash(:sha256, pk <> slug)
    QuaggaDef.derived_log_base(folded, @family)
  end

  @doc """
  The data-channel `log_id` for an application on one device facet.

  The facet occupies the high 8 bits, giving each device its own log inside
  the channel.

  ## Examples

      iex> base = Catenary.Apps.app_base("ExampleAuthor1", "example-app")
      iex> Catenary.Apps.app_log_id("ExampleAuthor1", "example-app", 0) == base
      true

      iex> Catenary.Apps.app_log_id("ExampleAuthor1", "example-app", 1) -
      ...>   Catenary.Apps.app_log_id("ExampleAuthor1", "example-app", 0)
      72057594037927936

  """
  @spec app_log_id(pk, slug, 0..255) :: non_neg_integer
  def app_log_id(pk, slug, device_facet)
      when is_binary(pk) and is_binary(slug) and device_facet in 0..255 do
    QuaggaDef.facet_log(app_base(pk, slug), device_facet)
  end

  @doc """
  Whether a log ID belongs to the app family (`0x2`).

  ## Examples

      iex> Catenary.Apps.app_family?(Catenary.Apps.manifest_log())
      true

      iex> Catenary.Apps.app_family?(777)
      false

  """
  @spec app_family?(term) :: boolean
  def app_family?(log_id) when is_integer(log_id),
    do: QuaggaDef.family_for_block(log_id) == :app

  def app_family?(_), do: false

  @doc """
  Whether a log ID is one of the three reserved kind bases.

  The app publish path rejects these unconditionally: an app may only append
  to its own derived channel, and a hash that happened to fold onto a kind
  sub-id would otherwise hand an app the manifest log.

  ## Examples

      iex> Catenary.Apps.kind_log?(Catenary.Apps.manifest_log())
      true

      iex> Catenary.Apps.kind_log?(QuaggaDef.facet_log(Catenary.Apps.artifact_log(), 1))
      true

      iex> Catenary.Apps.kind_log?(
      ...>   Catenary.Apps.app_base("ExampleAuthor1", "example-app")
      ...> )
      false

  """
  @spec kind_log?(term) :: boolean
  def kind_log?(log_id) when is_integer(log_id) do
    QuaggaDef.base_log(log_id) in @kind_logs
  end

  def kind_log?(_), do: false

  @doc """
  Whether a log ID is an app data channel: app family, and not a kind base.

  ## Examples

      iex> Catenary.Apps.data_channel?(
      ...>   Catenary.Apps.app_base("ExampleAuthor1", "example-app")
      ...> )
      true

      iex> Catenary.Apps.data_channel?(Catenary.Apps.manifest_log())
      false

      iex> Catenary.Apps.data_channel?(777)
      false

  """
  @spec data_channel?(term) :: boolean
  def data_channel?(log_id), do: app_family?(log_id) and not kind_log?(log_id)

  @doc """
  Check an entry's `app` field against the signed author and the log it
  arrived on.

  The `app` string is attacker-controlled CBOR, so a reader never trusts it.
  It is parsed, the key half is required to equal the *signed* author, and
  the derived base is recomputed from that author and the claimed slug and
  compared with the log the entry actually came from. Kind bases are refused
  outright — an app must not claim the manifest log as its channel.

  ## Examples

      iex> pk = "ExampleAuthor1"
      iex> Catenary.Apps.verify_channel(pk, pk <> "/example-app", Catenary.Apps.app_base(pk, "example-app"))
      :ok

      iex> pk = "ExampleAuthor1"
      iex> Catenary.Apps.verify_channel(
      ...>   pk,
      ...>   pk <> "/example-app",
      ...>   Catenary.Apps.app_base(pk, "other-app")
      ...> )
      {:error, :mismatch}

      iex> pk = "ExampleAuthor1"
      iex> Catenary.Apps.verify_channel("ExampleAuthor2", pk <> "/example-app", Catenary.Apps.app_base(pk, "example-app"))
      {:error, :author_mismatch}

      iex> pk = "ExampleAuthor1"
      iex> Catenary.Apps.verify_channel(pk, pk <> "/example-app", Catenary.Apps.manifest_log())
      {:error, :kind_base}

  """
  @spec verify_channel(pk, term, term) ::
          :ok
          | {:error,
             :bad_args
             | :bad_app_id
             | :invalid_slug
             | :not_app_log
             | :kind_base
             | :author_mismatch
             | :mismatch}
  def verify_channel(author_pk, claimed_app, log_id)
      when is_binary(author_pk) and is_binary(claimed_app) and is_integer(log_id) do
    base = QuaggaDef.base_log(log_id)

    cond do
      not app_family?(base) -> {:error, :not_app_log}
      kind_log?(base) -> {:error, :kind_base}
      true -> match_claim(author_pk, claimed_app, base)
    end
  end

  def verify_channel(_, _, _), do: {:error, :bad_args}

  defp match_claim(author_pk, claimed_app, base) do
    case parse_app_id(claimed_app) do
      {:ok, {pk, slug}} when pk == author_pk ->
        if app_base(pk, slug) == base, do: :ok, else: {:error, :mismatch}

      {:ok, _other} ->
        {:error, :author_mismatch}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
