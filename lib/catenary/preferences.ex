defmodule Catenary.Preferences do
  @moduledoc """
  End user preference persistence
  """

  # When adding a key here be sure to create function
  # heads for is_valid? to maintain the sanity of the store
  # Provide resonable defaults. We'd prefer not to use these
  # defaults as "unset" signals.. just working values.
  @keys [:identity, :clump_id, :shown, :view, :facet_id, :entry]
  def keys(), do: @keys

  defp default(:identity) do
    # It's hard to get into a state where this is unset and
    # we'll destroy an extant identity with a static name
    # Nevertheless, I don't wan to leave a "how many times
    # was this comment wrong?" counter here.
    rando = "catenary-user-" <> BaseX.Base62.encode(:crypto.strong_rand_bytes(2))
    id = Baobab.Identity.create(rando)
    # We do end up having to come through here a couple times before they might 
    # set the preference themselves so we set it ourselves
    set(:identity, id)
    id
  end

  defp default(:view), do: :prefs

  defp default(:entry), do: {:profile, get(:identity)}

  defp default(:clump_id),
    do: Application.get_env(:catenary, :clumps) |> Map.keys() |> hd

  defp default(:shown), do: MapSet.new()

  defp default(:facet_id), do: 0

  # `:identity` should in the known list when it is set
  defp is_valid?(identity, :identity),
    do: is_binary(identity) && Enum.any?(Baobab.Identity.list(), fn {_, k} -> k == identity end)

  # `:shown` should be a map of mapsets.
  # We'll hope they keep the values sane on their own
  defp is_valid?(val, :shown) when is_map(val), do: true
  defp is_valid?(_, :shown), do: false

  # This is all confused at present, so assume it's fine.
  defp is_valid?(_, :entry), do: true

  defp is_valid?(clump_id, :clump_id),
    do: Map.has_key?(Application.get_env(:catenary, :clumps), clump_id)

  # Views are always atoms, for now
  defp is_valid?(view, :view), do: is_atom(view)

  defp is_valid?(facet_id, :facet_id)
       when is_integer(facet_id) and facet_id >= 0 and facet_id <= 255,
       do: true

  defp is_valid?(_, :facet_id), do: false

  def get(key) when key in @keys do
    Catenary.dets_open(:prefs)

    val =
      case :dets.lookup(:prefs, key) do
        [] ->
          default(key)

        [{^key, val}] ->
          case is_valid?(val, key) do
            true -> val
            false -> default(key)
          end
      end

    Catenary.dets_close(:prefs)
    val
  end

  def get(_, _), do: {:error, "No such key"}

  def set(key, value) when key in @keys do
    case is_valid?(value, key) do
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

  def mark_all_entries(:unshown),
    do: update(:shown, fn m -> Map.merge(m, %{get(:clump_id) => MapSet.new()}) end)

  def mark_all_entries(:shown),
    do:
      update(:shown, fn m ->
        Map.merge(m, %{get(:clump_id) => MapSet.new(Baobab.all_entries(get(:clump_id)))})
      end)

  def mark_all_entries(_), do: {:error, "mark_all_entries/1 takes an atom (:shown, :unshown)"}

  def mark_entry(:shown, entry) do
    update(:shown, fn m ->
      Map.update(m, get(:clump_id), MapSet.new([entry]), fn ms -> MapSet.put(ms, entry) end)
    end)
  end

  def mark_entry(:unshown, entry) do
    update(:shown, fn m ->
      Map.update(m, get(:clump_id), MapSet.new(), fn ms -> MapSet.delete(ms, entry) end)
    end)
  end

  def mark_entry_type(how, type) do
    lids = QuaggaDef.logs_for_name(type)

    :clump_id
    |> get
    |> Baobab.all_entries()
    |> Enum.filter(fn {_, l, _} -> l in lids end)
    |> Enum.map(fn e -> mark_entry(how, e) end)
  end

  def shown?(entry),
    do: get(:shown) |> Map.get(get(:clump_id), MapSet.new()) |> MapSet.member?(entry)
end
