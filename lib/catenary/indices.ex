defmodule Catenary.Indices do
  alias Catenary.IndexWorker.Status

  @moduledoc """
  Functions to manage indices
  """

  # This list is a problem
  # Not one I am going to solve today
  @indices [
    :oases,
    :references,
    :tags,
    :reactions,
    :aliases,
    :timelines,
    :mentions,
    :about,
    :images,
    :graph
  ]
  @table_options [:public, :named_table]

  def status, do: Status.get_all()

  def update(indices \\ @indices)
  def update(index) when not is_list(index), do: update([index])
  def update([]), do: :ok

  def update([index | rest]) do
    GenServer.cast(index, :update)
    update(rest)
  end

  # Cast :update to every index worker, bypassing the store-hash gate used
  # by update/0/1. Used once at startup after Baobab's Log.Acceptor has had
  # time to populate :status dets, so workers index against the live store.
  def force_update(indices \\ @indices)

  def force_update(index) when not is_list(index), do: force_update([index])

  def force_update([]), do: :ok

  def force_update([index | rest]) do
    GenServer.cast(index, :update)
    force_update(rest)
  end

  def force_rebuild(indices \\ @indices)
  def force_rebuild(index) when not is_list(index), do: force_rebuild([index])
  def force_rebuild([]), do: :ok

  def force_rebuild([index | rest]) do
    GenServer.cast(index, :force_rebuild)
    force_rebuild(rest)
  end

  def reset do
    empty_tables(@indices)
  end

  def empty_tables([]), do: :ok

  def empty_tables([curr | rest]) do
    empty_table(curr)
    empty_tables(rest)
  end

  def empty_table(name) do
    case name in :ets.all() do
      true -> :ets.delete_all_objects(name)
      false -> :ets.new(name, @table_options)
    end
  end

  def published_date(data) when is_map(data) do
    case data["published"] do
      nil ->
        ""

      t ->
        case DateTime.from_iso8601(t, :extended) do
          {:ok, dt, _} -> DateTime.to_unix(dt)
          _ -> ""
        end
    end
  end

  def published_date(_), do: ""
end
