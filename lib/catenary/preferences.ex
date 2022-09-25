defmodule Catenary.Preferences do
  @moduledoc """
  End user preference persistence
  """

  # When adding a key here be sure to create function
  # heads for enum listing acceptable values or [] if free form
  # default which will generate a value if missing from the db
  @keys [:identity, :clump_id, :shown]

  defp default(:identity) do
    case Baobab.identities() do
      [{nick, _pk} | _] -> nick
      _ -> "catenary-user"
    end
  end

  defp default(:clump_id), do: "Quagga"
  defp default(:shown), do: MapSet.new()

  defp enum(:identity), do: []
  defp enum(:shown), do: []
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

  def update(key, fun) when key in @keys and is_function(fun, 1) do
    val = get(key) |> fun.()
    set(key, val)
  end

  def update(_, _), do: {:error, "update/2 requires a defined key and function/1 to apply"}

  def mark_all_entries(:unshown), do: set(:shown, MapSet.new())

  def mark_all_entries(:shown), do: set(:shown, MapSet.new(Baobab.all_entries()))

  def mark_all_entries(_), do: {:error, "mark_all_entries/1 takes an atom (:shown, :unshown)"}

  def shown?(entry), do: get(:shown) |> MapSet.member?(entry)
end
