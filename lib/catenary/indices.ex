defmodule Catenary.Indices do
  require Logger

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

  def status(indices \\ @indices)
  def status(index) when not is_list(index), do: status([index])
  def status(indices), do: status(indices, [])
  def status([], acc), do: acc |> Enum.reverse()

  def status([index | rest], acc) do
    status(rest, [GenServer.call(index, :status) | acc])
  end

  def update(indices \\ @indices)
  def update(index) when not is_list(index), do: update([index])
  def update([]), do: :ok

  def update([index | rest]) do
    # For now we ignore the call reply
    # We also provide no way to supply a subset
    # which is fine because the indexers don't handle that
    GenServer.call(index, {:update, []})
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
