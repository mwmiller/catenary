defmodule Catenary.State do
  @moduledoc """
  Hold bits of indexed state
  """

  use Agent

  @clean_state %{aliases: %{}, profile: [], oases: []}

  def start_link(_arg) do
    Agent.start_link(fn -> @clean_state end, name: __MODULE__)
  end

  def reset(), do: Agent.update(__MODULE__, fn _ -> @clean_state end)

  def get(which) do
    Agent.get(__MODULE__, fn s -> Map.get(s, which) end)
  end

  def set_aliases(new_map) do
    Agent.update(__MODULE__, fn s ->
      %{aliases: prev} = s
      Map.merge(s, %{aliases: Map.merge(prev, new_map)})
    end)
  end

  def set_profile() do
    # This might become more complicated and inclusive later
    whoami = Catenary.Preferences.get(:identity)

    profile_items =
      case :ets.lookup(:mentions, {"", whoami}) do
        [] -> []
        [{{"", ^whoami}, items}] -> Enum.map(items, fn {_t, e} -> e end)
      end

    Agent.update(__MODULE__, fn s -> Map.merge(s, %{profile: profile_items}) end)
  end

  def update_oases(recents) do
    Agent.update(__MODULE__, fn s ->
      %{oases: prev} = s

      full =
        (prev ++ recents)
        |> Enum.uniq_by(fn m -> m["name"] end)
        |> Enum.sort_by(fn m -> Map.get(m, "running") end, :desc)

      Map.merge(s, %{oases: full})
    end)
  end
end
