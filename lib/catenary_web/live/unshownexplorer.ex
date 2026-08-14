defmodule Catenary.Live.UnshownExplorer do
  @moduledoc """
  LiveComponent rendering an explorer of unshown entries.
  """
  use Phoenix.LiveComponent
  alias Catenary.Display

  @display_limit 11
  @impl true
  def update(%{which: which, clump_id: clump_id} = assigns, socket) do
    {:ok, assign(socket, Map.merge(assigns, %{card: extract(which, clump_id)}))}
  end

  @impl true
  def render(%{card: :none} = assigns), do: Catenary.GeneriCard.no_data_card(assigns)

  def render(%{card: :error} = assigns), do: Catenary.GeneriCard.error_card(assigns)

  def render(assigns) do
    ~H"""
    <div id="unshown-explore-wrap" class="content-wrap">
      <div class="flex flex-col gap-5">
        <h1 class="text-lg font-semibold text-slate-800 dark:text-slate-100">Unshown Explorer</h1>
        <%= for {type, entries, estring, size} <- @card do %>
          <div class="flex flex-col gap-2">
            <h3 class="text-xs tracking-wide text-slate-400 dark:text-slate-500 flex items-center gap-2">
              <button
                phx-click="shown-set"
                value={estring}
                title="Mark shown"
                class="px-1 rounded text-slate-500 dark:text-slate-400 hover:text-slate-800 dark:hover:text-slate-100 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors"
              >
                ∅
              </button>
              {type}
            </h3>
            <div class="grid grid-cols-3 gap-2">
              {entries}
              <%= if size == :more do %>
                <p class="text-xs text-slate-400 dark:text-slate-500">(◎+)</p>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp extract(:all, clump_id) do
    shown = Catenary.Preferences.get(:shown) |> Map.get(clump_id, MapSet.new())

    Baobab.all_entries(clump_id)
    |> MapSet.new()
    |> MapSet.difference(shown)
    |> MapSet.to_list()
    |> group_entries(clump_id)
  end

  defp extract(_, _), do: :none

  defp group_entries(entries, clump_id) do
    entries
    |> Enum.group_by(fn {_, l, _} -> QuaggaDef.base_log(l) end)
    |> Map.to_list()
    |> prettify(clump_id)
    |> Enum.sort(:asc)
  end

  defp prettify(entries, clump_id, acc \\ [])
  defp prettify([], _, acc), do: acc

  defp prettify([{k, v} | rest], clump_id, acc) do
    size =
      case length(v) > @display_limit do
        true -> :more
        false -> :all
      end

    display_list =
      v |> Enum.sort_by(&elem(&1, 2)) |> Enum.take(@display_limit) |> display_entries(clump_id)

    group = {Display.pretty_log_name(k), display_list, Catenary.index_list_to_string(v), size}

    prettify(rest, clump_id, [group | acc])
  end

  defp display_entries(entries, clump_id, acc \\ [])

  defp display_entries([], _, acc),
    do: acc |> Enum.reverse() |> Enum.join("") |> Phoenix.HTML.raw()

  defp display_entries([entry | rest], clump_id, acc),
    do: display_entries(rest, clump_id, [for_display(entry, clump_id) | acc])

  defp for_display({a, l, e} = entry, clump_id) do
    val =
      try do
        %Baobab.Entry{payload: payload} = Baobab.log_entry(a, e, log_id: l, clump_id: clump_id)
        # Some entries are not CBOR, we can just fail for now
        # Likely more logic is coming.
        {:ok, data, ""} = CBOR.decode(payload)
        Display.avatar_view_entry_button(entry, Catenary.Display.entry_title(l, data))
      rescue
        _ -> Display.entry_icon_link(entry, 4)
      end

    "<div>" <> val <> "</div>"
  end
end
