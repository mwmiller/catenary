defmodule Catenary.State do
  @moduledoc """
  Hold bits of indexed state
  """

  use Agent

  def start_link(_arg) do
    Agent.start_link(fn -> %{aliases: %{}} end, name: __MODULE__)
  end

  def get(which) do
    Agent.get(__MODULE__, fn s -> Map.get(s, which) end)
  end

  def set_aliases(new_map) do
    Agent.update(__MODULE__, fn s -> Map.merge(s, %{aliases: new_map}) end)
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
end
