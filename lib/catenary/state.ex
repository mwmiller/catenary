defmodule Catenary.State do
  @moduledoc """
  Hold bits of indexed state
  """

  use Agent

  @clean_state %{aliases: %{}, profile: [], oases: []}

  def start_link(_arg) do
    Agent.start_link(fn -> @clean_state end, name: __MODULE__)
  end

  def reset, do: Agent.update(__MODULE__, fn _ -> @clean_state end)

  def get(which) do
    Agent.get(__MODULE__, fn s -> Map.get(s, which) end)
  end

  def set_aliases(new_map) do
    Agent.update(__MODULE__, fn s ->
      %{aliases: prev} = s
      Map.merge(s, %{aliases: Map.merge(prev, new_map)})
    end)
  end

  def set_profile do
    # This might become more complicated and inclusive later
    whoami = Catenary.Preferences.get(:identity)

    profile_items =
      case :ets.lookup(:mentions, {"", whoami}) do
        [] -> []
        [{{"", ^whoami}, items}] -> Enum.map(items, fn {_t, e} -> e end)
      end

    Agent.update(__MODULE__, fn s -> Map.merge(s, %{profile: profile_items}) end)
  end

  @max_oases 11

  def clear_oases, do: Agent.update(__MODULE__, fn s -> %{s | oases: []} end)

  def update_oases(recents) do
    Agent.update(__MODULE__, fn s ->
      %{oases: prev} = s

      # An oasis node is identified by its host:port; a rename produces a new
      # announcement with the same host:port but a different name, so dedup on
      # the node identity. Keep the newest entry (highest seqnum, stashed under
      # :id as {author, log, seqnum}) so a renamed oasis is shown once, with its
      # latest name, and never duplicates.
      full =
        (prev ++ recents)
        |> Enum.sort_by(&oasis_seq/1, :desc)
        |> Enum.uniq_by(&oasis_key/1)
        |> Enum.sort_by(fn m -> Map.get(m, "running") end, :desc)
        |> Enum.take(@max_oases)

      Map.merge(s, %{oases: full})
    end)
  end

  defp oasis_key(m), do: {m["host"], m["port"]}

  defp oasis_seq(m) do
    case m[:id] do
      {_, _, s} -> s
      _ -> 0
    end
  end
end
