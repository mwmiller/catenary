defmodule Catenary.Indices do
  alias Catenary.IndexWorker.Status

  @moduledoc """
  Functions to manage indices
  """

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
    :challenges,
    :graph
  ]
  @table_options [:public, :named_table]

  def status, do: Status.get_all()

  # Cast :update to every index worker. The worker's store-hash gate skips
  # the full log pass when nothing has changed.
  def update(indices \\ @indices)
  def update(index) when not is_list(index), do: update([index])

  def update(indices) when is_list(indices) do
    Enum.each(indices, &GenServer.cast(&1, :update))
  end

  # Alias kept for callers that want the intent to be explicit.
  def force_update(indices \\ @indices), do: update(indices)

  def force_rebuild(indices \\ @indices)
  def force_rebuild(index) when not is_list(index), do: force_rebuild([index])

  def force_rebuild(indices) when is_list(indices) do
    Enum.each(indices, &GenServer.cast(&1, :force_rebuild))
  end

  def reset do
    empty_tables(@indices)
  end

  def empty_tables(indices) when is_list(indices) do
    Enum.each(indices, &empty_table/1)
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
