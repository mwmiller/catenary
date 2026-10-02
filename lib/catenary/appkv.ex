defmodule Catenary.AppKV do
  @moduledoc """
  App-scoped local key/value storage.

  One table, keyed `{clump_id, pk, slug, key}`, so an app can only ever
  reach its own keys: the publisher (`pk`) and the listing name (`slug`)
  are part of the key, not a prefix an app supplies itself.

  Nothing here leaves the machine. Keys are not published, not gossiped
  and not written to the spool, so this store is invisible to every other
  participant and is wiped along with the app's local data. Apps that want
  state others can see publish it to their own derived log instead.

  Apps reach this store only through `Catenary.AppHost`, which owns the
  operation allow-list; this module is the table, not the door.
  """

  use GenServer

  @table :app_kv

  @type app :: Catenary.AppHost.app()
  @type key :: binary

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  The value stored for `key`, or `{:error, :not_found}`.

  A missing key is a normal answer an app has to handle, not a failure of
  the store, so it never raises and never looks like a rejected operation.
  """
  @spec get(app, key) :: {:ok, term} | {:error, :not_found}
  def get(%{clump_id: c, pk: p, slug: s}, key) when is_binary(key) do
    case :ets.lookup(@table, {c, p, s, key}) do
      [{_k, value}] -> {:ok, value}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Store `value` under `key` for this app.

  Any term can be stored; the harness is responsible for keeping what it
  sends to something it can encode again.
  """
  @spec put(app, key, term) :: :ok
  def put(%{clump_id: c, pk: p, slug: s}, key, value) when is_binary(key) do
    true = :ets.insert(@table, {{c, p, s, key}, value})
    :ok
  end

  @doc """
  Drop every key belonging to one app.

  Called when an installation's local data is cleared, so a re-install
  starts from the same empty store an app would have seen on first run.
  """
  @spec clear(app) :: :ok
  def clear(%{clump_id: c, pk: p, slug: s}) do
    :ets.match_delete(@table, {{c, p, s, :_}, :_})
    :ok
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end
end
