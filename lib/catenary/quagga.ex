defmodule Catenary.Quagga do
  @moduledoc """
  Related to participating in the `Quagga` clump
  """

  @log_to_def %{
    0 => %{encoding: :raw, type: "text/plain", name: :test},
    533 => %{encoding: :raw, type: :map, name: :reply},
    8483 => %{encoding: :cbor, type: :map, name: :oasis},
    360_360 => %{encoding: :cbor, type: :map, name: :journal},
    808_001 => %{encoding: :raw, type: "image/jpg", name: :jpg},
    808_002 => %{encoding: :raw, type: "image/png", name: :png},
    808_003 => %{encoding: :raw, type: "image/gif", name: :gif}
  }

  @name_to_log @log_to_def |> Enum.reduce(%{}, fn {l, %{name: n}}, a -> Map.put(a, n, l) end)

  def log_def(n), do: Map.get(@log_to_def, n, %{})
  def log_id_for_name(n), do: Map.get(@name_to_log, n, :unknown)
  # Thsi should work off the def, but I need more metadata and
  # I am crnaky this morning.
  def log_type(), do: [:test, :oasis, :journal] |> Enum.random()
end
