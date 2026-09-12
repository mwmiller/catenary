defmodule Catenary.BlockLog do
  @base_mask 0x00FFFFFFFFFFFFFF
  @family_mask 0x00FF000000000000

  @moduledoc """
  Helpers for blocking and unblocking log types and families by name using
  Baobab ClumpMeta pattern blocks.
  """

  @spec log_name_to_base(atom) :: integer
  defp log_name_to_base(name) do
    name |> QuaggaDef.logs_for_name() |> hd() |> Bitwise.band(@base_mask)
  end

  @doc """
  Block all facets of a log type by name and purge stored entries.
  """
  @spec block_name(atom, binary) :: [map]
  def block_name(name, clump_id \\ "default") when is_atom(name) do
    base = log_name_to_base(name)
    result = Baobab.ClumpMeta.block_pattern(%{op: :eq, mask: @base_mask, v: base}, clump_id)
    purge_log_entries(name, clump_id)
    result
  end

  @doc """
  Purge all stored Baobab entries whose base_log matches the given log type name.
  """
  @spec purge_log_entries(atom, binary) :: :ok
  def purge_log_entries(name, clump_id \\ "default") when is_atom(name) do
    base = log_name_to_base(name)

    Baobab.all_entries(clump_id)
    |> Enum.filter(fn {_, l, _} -> Bitwise.band(l, @base_mask) == base end)
    |> Enum.each(fn {a, l, _e} ->
      Baobab.purge(a, log_id: l, clump_id: clump_id)
    end)

    :ok
  end

  @doc """
  Unblock all facets of a log type by name.
  """
  @spec unblock_name(atom, binary) :: [map]
  def unblock_name(name, clump_id \\ "default") when is_atom(name) do
    base = log_name_to_base(name)
    Baobab.ClumpMeta.unblock_pattern(%{op: :eq, mask: @base_mask, v: base}, clump_id)
  end

  @doc """
  Check whether a log type name is blocked by a pattern.
  """
  @spec blocked_name?(atom, binary) :: boolean
  def blocked_name?(name, clump_id \\ "default") when is_atom(name) do
    base = log_name_to_base(name)
    Baobab.ClumpMeta.pattern_matches?(base, clump_id)
  end

  @doc """
  Check whether a log_id is blocked by a pattern.
  """
  @spec blocked_id?(integer, binary) :: boolean
  def blocked_id?(log_id, clump_id \\ "default") when is_integer(log_id) do
    Baobab.ClumpMeta.pattern_matches?(log_id, clump_id)
  end

  @doc """
  Block all derived logs of a given family tag by creating a family
  pattern (mask bits 48-55). Also purges any existing stored entries
  that match the family so they are no longer accessible.
  """
  @spec block_family(integer, binary) :: [map]
  def block_family(family_tag, clump_id \\ "default")
      when is_integer(family_tag) and family_tag >= 1 and family_tag <= 255 do
    result =
      Baobab.ClumpMeta.block_pattern(
        %{op: :eq, mask: @family_mask, v: Bitwise.bsl(family_tag, 48)},
        clump_id
      )

    purge_family_entries(family_tag, clump_id)
    result
  end

  @doc """
  Purge all stored Baobab entries whose log_id belongs to the given family.
  """
  @spec purge_family_entries(integer, binary) :: :ok
  def purge_family_entries(family_tag, clump_id \\ "default")
      when is_integer(family_tag) and family_tag >= 1 and family_tag <= 255 do
    target = Bitwise.bsl(family_tag, 48)

    Baobab.all_entries(clump_id)
    |> Enum.filter(fn {_, l, _} -> Bitwise.band(l, @family_mask) == target end)
    |> Enum.each(fn {a, l, _e} ->
      Baobab.purge(a, log_id: l, clump_id: clump_id)
    end)

    :ok
  end

  @doc """
  Unblock a family tag.
  """
  @spec unblock_family(integer, binary) :: [map]
  def unblock_family(family_tag, clump_id \\ "default")
      when is_integer(family_tag) and family_tag >= 1 and family_tag <= 255 do
    Baobab.ClumpMeta.unblock_pattern(
      %{op: :eq, mask: @family_mask, v: Bitwise.bsl(family_tag, 48)},
      clump_id
    )
  end

  @doc """
  Check whether a family tag is blocked by a pattern.
  """
  @spec blocked_family?(integer, binary) :: boolean
  def blocked_family?(family_tag, clump_id \\ "default")
      when is_integer(family_tag) and family_tag >= 1 and family_tag <= 255 do
    Baobab.ClumpMeta.pattern_matches?(Bitwise.bsl(family_tag, 48), clump_id)
  end

  @doc """
  Block all currently defined families. Returns the list of family names
  that were blocked.
  """
  @spec block_all_families(binary) :: [atom]
  def block_all_families(clump_id \\ "default") do
    for {name, tag} <- QuaggaDef.families() do
      block_family(tag, clump_id)
      name
    end
  end

  @doc """
  Convert old literal log_id blocks to pattern blocks.

  Groups literal integer blocks by their base_log (lower 56 bits).
  When all 256 facets of a base_log are present, replaces them with
  a single pattern block and removes the individual literals.
  """
  @spec convert_literals(binary) :: :ok
  def convert_literals(clump_id \\ "default") do
    literals =
      Baobab.ClumpMeta.blocks_list(clump_id)
      |> Enum.filter(&is_integer/1)

    # Group by base_log (lower 56 bits)
    grouped = Enum.group_by(literals, &Bitwise.band(&1, @base_mask))

    for {base, ids} <- grouped, length(ids) >= 256 do
      # Remove the individual literal blocks
      Enum.each(ids, &Baobab.ClumpMeta.unblock(&1, clump_id))
      # Add a single pattern block
      Baobab.ClumpMeta.block_pattern(%{op: :eq, mask: @base_mask, v: base}, clump_id)
    end

    :ok
  end
end
