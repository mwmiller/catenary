defmodule Catenary.Quagga do
  @moduledoc """
  Related to participating in the `Quagga` clump
  """

  @log_to_def %{
    0 => %{encoding: :raw, type: "text/plain", name: :test},
    53 => %{encoding: :cbor, type: :map, name: :alias},
    533 => %{encoding: :cbor, type: :map, name: :reply},
    8483 => %{encoding: :cbor, type: :map, name: :oasis},
    360_360 => %{encoding: :cbor, type: :map, name: :journal},
    808_001 => %{encoding: :raw, type: "image/jpg", name: :jpg},
    808_002 => %{encoding: :raw, type: "image/png", name: :png},
    808_003 => %{encoding: :raw, type: "image/gif", name: :gif}
  }

  @name_to_log @log_to_def |> Enum.reduce(%{}, fn {l, %{name: n}}, a -> Map.put(a, n, l) end)
  @encoding_to_logs @log_to_def
                    |> Enum.reduce(%{}, fn {l, %{encoding: e}}, a ->
                      Map.update(a, e, [l], fn x -> [l | x] end)
                    end)

  def log_def(n), do: Map.get(@log_to_def, n, %{})
  def log_id_for_name(n), do: Map.get(@name_to_log, n, :unknown)
  def log_ids_for_encoding(e), do: Map.get(@encoding_to_logs, e, [])

  # This should work off the def, but I need more metadata and
  # I am cranky this morning.
  def log_type(), do: [:test, :oasis, :journal] |> Enum.random()
end
