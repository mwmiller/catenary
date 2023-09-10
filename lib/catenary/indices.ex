defmodule Catenary.Indices do
  require Logger
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

  def status(), do: Status.get_all()

  def update(indices \\ @indices)
  def update(index) when not is_list(index), do: update([index])
  def update([]), do: :ok

  def update([index | rest]) do
    GenServer.cast(index, :update)
    update(rest)
  end

  def reset() do
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
        t
        |> Timex.parse!("{ISO:Extended}")
        |> Timex.to_unix()
    end
  end

  def published_date(_), do: ""
end
