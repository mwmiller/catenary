defmodule Catenary.AppHost do
  @moduledoc """
  The single choke point every app-facing host operation goes through.

  An app never reads the spool, the index tables or the filter preferences
  directly. It sends an operation name with some arguments and this module
  decides whether to answer, applying the same visibility rules the
  viewer's own UI applies. An operation added anywhere else would reach
  local data without those rules, so there is deliberately only this one
  door.

  Two things belong to the caller rather than to this module:

    * **Building `app`.** The context names which listing is running
      (`pk`, `slug`) and which store it runs against (`clump_id`). The
      LiveView must assemble it from its own assigns, never from anything
      a worker sent, or an app could widen its scope into another app's
      keys.

    * **Transport.** `handle/3` returns Elixir terms, and payload bytes
      are returned as a `CBOR.Tag` rather than a bare binary: Elixir
      encodes a plain binary as a CBOR *text* string, which would put an
      arbitrary log payload through a UTF-8 conversion on its way to the
      worker. The bridge that puts a reply on the wire just encodes what
      comes back from here.
  """

  alias Catenary.AppKV

  @type app :: %{clump_id: String.t(), pk: binary, slug: String.t()}

  # The operation allow-list. Matching on the names themselves rather than
  # turning a wire string into an atom means an unrecognised operation
  # never creates an atom and never reaches a read.
  @ops ~w(log_read storage_get storage_set)

  @doc """
  Every operation this host answers to. Anything else is refused without
  a lookup, which is what makes `handle/3` a boundary rather than a
  convenience wrapper.
  """
  @spec ops() :: [String.t()]
  def ops, do: @ops

  @doc """
  Build the app context from server-side state.
  """
  @spec app(String.t(), binary, String.t()) :: app
  def app(clump_id, pk, slug)
      when is_binary(clump_id) and is_binary(pk) and is_binary(slug),
      do: %{clump_id: clump_id, pk: pk, slug: slug}

  @doc """
  Run one host operation for `app`, named by `op`.

  Returns `{:ok, value}` or `{:error, reason}`. Being blocked, missing or
  unsupported is an answer the app has to handle rather than a crash: the
  worker keeps running either way.
  """
  @spec handle(app, String.t(), map) :: {:ok, term} | {:error, term}
  def handle(app, op, args) when is_binary(op) and is_map(args) do
    case app do
      %{clump_id: c, pk: p, slug: s} when is_binary(c) and is_binary(p) and is_binary(s) ->
        dispatch(app, op, args)

      _ ->
        {:error, :bad_app}
    end
  end

  # A malformed message is an error the caller can report, not a reason to
  # take the LiveView down: this function is reachable from the wire.
  def handle(_app, _op, _args), do: {:error, :bad_args}

  defp dispatch(app, op, args) do
    case op do
      "log_read" -> log_read(app, args)
      "storage_get" -> storage_get(app, args)
      "storage_set" -> storage_set(app, args)
      _ -> {:error, :unsupported_op}
    end
  end

  defp log_read(%{clump_id: clump_id}, args) do
    with {:ok, author} <- arg(args, :author),
         {:ok, log_id} <- arg(args, :log_id),
         {:ok, seq} <- arg(args, :seq),
         {:ok, author} <- as_author(author),
         {:ok, log_id} <- as_log_id(log_id),
         {:ok, seq} <- as_seq(seq),
         :ok <- visible(author, log_id, seq, clump_id),
         {:ok, payload} <- fetch(author, log_id, seq, clump_id) do
      {:ok, payload}
    else
      :error -> {:error, :bad_args}
      {:error, _} = err -> err
    end
  end

  defp storage_get(app, args) do
    case arg(args, :key) do
      {:ok, key} when is_binary(key) -> AppKV.get(app, key)
      _ -> {:error, :bad_args}
    end
  end

  defp storage_set(app, args) do
    with {:ok, key} when is_binary(key) <- arg(args, :key),
         {:ok, value} <- arg(args, :value) do
      :ok = AppKV.put(app, key, value)
      {:ok, :stored}
    else
      _ -> {:error, :bad_args}
    end
  end

  # One check covers everything that decides whether an entry may be seen:
  # literal author, log and {author, log} blocks, the base-log pattern
  # blocks `Catenary.BlockLog.block_name/2` writes, and the family pattern
  # blocks `Catenary.BlockLog.block_family/2` writes. It is the same
  # classifier the rest of the app filters a list of entries with, which is
  # what keeps an app from seeing something the viewer would hide.
  defp visible(author, log_id, seq, clump_id) do
    case Baobab.ClumpMeta.filter_blocked([{author, log_id, seq}], clump_id) do
      [_entry] -> :ok
      [] -> {:error, :blocked}
      # A clump the store does not know. Passing it through rather than
      # reading it as `false` keeps an unusable context from being taken
      # for a permission grant.
      {:error, _} = err -> err
    end
  end

  defp fetch(author, log_id, seq, clump_id) do
    case Baobab.log_entry(author, seq, log_id: log_id, clump_id: clump_id) do
      %Baobab.Entry{payload: payload} -> {:ok, %CBOR.Tag{tag: :bytes, value: payload}}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :missing}
    end
  end

  # Blocks are recorded against the base62 form of an author, so an author
  # given as an alias name or a raw key has to be normalised before it is
  # compared against them. Without this an app could sidestep an author
  # block simply by naming the author differently than the block does.
  defp as_author(author) when is_binary(author) and author != "" do
    case Baobab.Identity.as_base62(author) do
      {:error, _} -> :error
      base62 -> {:ok, base62}
    end
  end

  defp as_author(_), do: :error

  defp as_log_id(log_id) when is_integer(log_id) and log_id >= 0, do: {:ok, log_id}
  defp as_log_id(_), do: :error

  defp as_seq(seq) when is_integer(seq) and seq > 0, do: {:ok, seq}
  defp as_seq("max"), do: {:ok, :max}
  defp as_seq(:max), do: {:ok, :max}
  defp as_seq(_), do: :error

  # Arguments arrive from the worker as JSON, so their keys are strings,
  # while internal callers use atoms. Both are accepted; a key from the
  # wire is never turned into an atom.
  defp arg(args, key) when is_atom(key) do
    case Map.fetch(args, key) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(args, Atom.to_string(key))
    end
  end
end
