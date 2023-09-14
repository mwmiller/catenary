defmodule Catenary.Live.UnshownExplorer do
  require Logger
  use Phoenix.LiveComponent

  @display_limit 17
  @impl true
  def update(%{which: which, clump_id: clump_id} = assigns, socket) do
    {:ok, assign(socket, Map.merge(assigns, %{card: extract(which, clump_id)}))}
  end

  @impl true
  def render(%{card: :none} = assigns), do: Catenary.GeneriCard.no_data_card(assigns)

  def render(%{card: :error} = assigns), do: Catenary.GeneriCard.error_card(assigns)

  def render(assigns) do
    ~L"""
     <div id="unshownexplore-wrap" class="col-span-2 overflow-y-auto max-h-screen m-2 p-x-2">
      <h1 class="text=center">Unshown Explorer</h1>
      <hr/>
      <%= for {type, entries, estring, size} <- @card do %>
        <h3 class="text-slate-600 dark:text-slate-300"><button phx-click="shown-set" value="<%= estring %>">∅</button>&nbsp;&nbsp;<%= type %></h3>
        <div class="grid grid-cols-5 my-2">
        <%= entries %>
        <%= if size == :more do %>
        <p class="text-xs">(◎+)</p>
        <% end %>
        </div>
      <% end %>
     </div>
    """
  end

  defp extract(:all, clump_id) do
    shown = Catenary.Preferences.get(:shown) |> Map.get(clump_id, MapSet.new())

    Baobab.all_entries(clump_id)
    |> MapSet.new()
    |> MapSet.difference(shown)
    |> MapSet.to_list()
    |> group_entries()
  end

  defp extract(_, _), do: :none

  defp group_entries(entries) do
    entries
    |> Enum.group_by(fn {_, l, _} -> QuaggaDef.base_log(l) end)
    |> Map.to_list()
    |> prettify([])
    |> Enum.sort(:asc)
  end

  defp prettify([], acc), do: acc

  defp prettify([{k, v} | rest], acc) do
    size =
      case length(v) > @display_limit do
        true -> :more
        false -> :all
      end

    display_list = v |> Enum.sort_by(&elem(&1, 2)) |> Enum.take(@display_limit) |> icon_entries()
    group = {Catenary.pretty_log_name(k), display_list, Catenary.index_list_to_string(v), size}

    prettify(rest, [group | acc])
  end

  defp icon_entries(entries) do
    entries
    |> Enum.reduce("", fn e, a ->
      a <> "<div>" <> Catenary.entry_icon_link(e, 4) <> "</div>"
    end)
    |> Phoenix.HTML.raw()
  end
end
