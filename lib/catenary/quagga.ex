defmodule Catenary.Quagga do
  import Bitwise

  @moduledoc """
  Related to participating in the `Quagga` clump
  """

  @base_log_bits 56
  @base_logs_end :math.pow(2, @base_log_bits) |> trunc |> then(fn n -> n - 1 end)
  @log_to_def %{
    0 => %{encoding: :raw, type: "text/plain", name: :test},
    53 => %{encoding: :cbor, type: :map, name: :alias},
    533 => %{encoding: :cbor, type: :map, name: :reply},
    749 => %{encoding: :cbor, type: :map, name: :tag},
    8483 => %{encoding: :cbor, type: :map, name: :oasis},
    360_360 => %{encoding: :cbor, type: :map, name: :journal},
    808_001 => %{encoding: :raw, type: "image/jpg", name: :jpg},
    808_002 => %{encoding: :raw, type: "image/png", name: :png},
    808_003 => %{encoding: :raw, type: "image/gif", name: :gif}
  }

  # This is essentially CBOR minus oasis
  @timeline_logs [:journal, :reply, :tag, :alias]
  @name_to_log @log_to_def |> Enum.reduce(%{}, fn {l, %{name: n}}, a -> Map.put(a, n, l) end)
  @encoding_to_logs @log_to_def
                    |> Enum.reduce(%{}, fn {l, %{encoding: e}}, a ->
                      Map.update(a, e, [l], fn x -> [l | x] end)
                    end)

  # This may go private once the Quagga API is squared away
  # As if it matters
  def log_id_unpack(n) when is_integer(n) do
    <<facet_id::integer-size(8), base_log::integer-size(@base_log_bits)>> =
      <<n::integer-size(64)>>

    {base_log, facet_id}
  end

  def log_id_unpack(_), do: :error

  def log_def(n) when is_integer(n) do
    {base_log, _} = log_id_unpack(n)
    Map.get(@log_to_def, base_log, %{})
  end

  def log_def(_), do: :error

  def base_log_for_name(n), do: Map.get(@name_to_log, n, :unknown)

  def base_log_for_id(n) do
    {base_log, _} = log_id_unpack(n)
    base_log
  end

  def log_ids_for_name(n) do
    @name_to_log
    |> Map.get(n)
    |> samebase_logs
  end

  def log_ids_for_encoding(e) do
    @encoding_to_logs
    |> Map.get(e, [])
    |> Enum.reduce([], fn bl, a -> [samebase_logs(bl) | a] end)
    |> List.flatten()
  end

  def facet_log(base_log, facet_id)
      when base_log <= @base_logs_end and facet_id <= 255 and facet_id >= 0 do
    base_log ||| facet_id <<< 56
  end

  def facet_log(_, _), do: :error

  for base_log <- Map.keys(@log_to_def) do
    matches = Enum.reduce(1..255, [base_log], fn i, a -> [base_log ||| i <<< 56 | a] end)
    defp samebase_logs(n) when n in unquote(matches), do: unquote(matches)
  end

  defp samebase_logs(_), do: []

  def timeline_logs, do: @timeline_logs
  def random_timeline_log(), do: @timeline_logs |> Enum.random()

  def pretty_log_name(log_id) do
    case log_id_unpack(log_id) do
      {base_log, _} ->
        base_log
        |> log_def()
        |> Map.get(:name)
        |> Atom.to_string()
        |> String.capitalize()

      _ ->
        ""
    end
  end
end
