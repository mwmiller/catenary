defmodule Catenary.Preferences do
  @moduledoc """
  End user preference persistence
  """

  # When adding a key here be sure to create function
  # heads for enum listing acceptable values or [] if free form
  # default which will generate a value if missing from the db
  @keys [:iconset, :identity, :clump_id]

  defp default(:iconset), do: :svg

  defp default(:identity) do
    case Baobab.identities() do
      [{nick, _pk} | _] -> nick
      _ -> "catenary-user"
    end
  end

  defp default(:clump_id), do: "Quagga"

  defp enum(:iconset), do: [:png, :svg]
  defp enum(:identity), do: []
  defp enum(:clump_id), do: []

  def get(key) when key in @keys do
    Catenary.dets_open(:prefs)

    val =
      case :dets.lookup(:prefs, key) do
        [] -> default(key)
        [{^key, val}] -> val
      end

    Catenary.dets_close(:prefs)
    val
  end

  def get(_, _), do: {:error, "No such key"}

  def set(key, value) when key in @keys do
    valok =
      case enum(key) do
        [] -> true
        okvals -> value in okvals
      end

    case valok do
      false ->
        {:error, "Improper value for key"}

      true ->
        Catenary.dets_open(:prefs)
        :dets.insert(:prefs, {key, value})
        Catenary.dets_close(:prefs)
    end
  end

  def set(_, _), do: {:error, "No such key"}
end
