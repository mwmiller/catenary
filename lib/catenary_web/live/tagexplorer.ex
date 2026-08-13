defmodule Catenary.Live.TagExplorer do
  @moduledoc """
  LiveComponent rendering an explorer of tag entries.
  """
  use Phoenix.LiveComponent

  @impl true
  def update(%{entry: which} = assigns, socket) do
    {:ok, assign(socket, Map.merge(assigns, %{card: extract(which)}))}
  end

  @impl true
  def render(%{card: :none} = assigns), do: Catenary.GeneriCard.no_data_card(assigns)

  def render(%{card: :error} = assigns), do: Catenary.GeneriCard.error_card(assigns)

  def render(assigns) do
    ~H"""
    <div id="tag-explore-wrap" class="col-span-2 overflow-y-auto max-h-screen m-2 px-2">
      <div class="flex flex-col gap-5">
        <h1 class="text-lg font-semibold text-slate-800 dark:text-slate-100">Tag Explorer</h1>
        <%= for g <- @card["tags"] do %>
          <div class="flex flex-row flex-wrap gap-2">
            {g}
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp extract(:all) do
    :ets.lookup(:tags, :display)
    |> then(fn
      [{_, items}] -> link_groups(items, [])
      _ -> []
    end)
    |> then(fn tags -> %{"tags" => tags} end)
  end

  defp extract(_), do: :none

  defp link_groups([], acc), do: Enum.reverse(acc)
  defp link_groups([tags | rest], acc), do: link_groups(rest, [to_links(tags) | acc])

  defp to_links(tags) do
    tags
    |> Enum.map(fn {t, _c} ->
      ~s(<button value=") <>
        t <>
        ~s(" phx-click="view-tag"><div class="rounded-lg border border-slate-200 dark:border-slate-700 p-2 hover:border-amber-500 dark:hover:border-amber-400 transition-colors"><p class="text-amber-700 dark:text-amber-300">) <>
        t <> ~s(</p></div></button>)
    end)
    |> Phoenix.HTML.raw()
  end
end
