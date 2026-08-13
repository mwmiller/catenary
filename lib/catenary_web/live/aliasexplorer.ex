defmodule Catenary.Live.AliasExplorer do
  @moduledoc """
  LiveComponent rendering an explorer for an alias entry.
  """
  use Phoenix.LiveComponent
  alias Catenary.Display

  @impl true
  def update(%{alias: which, aliases: aliases} = assigns, socket) do
    {:ok, assign(socket, Map.merge(assigns, %{card: extract(which, aliases)}))}
  end

  @impl true
  def render(%{card: :none} = assigns), do: Catenary.GeneriCard.no_data_card(assigns)

  def render(%{card: :error} = assigns), do: Catenary.GeneriCard.error_card(assigns)

  def render(assigns) do
    ~H"""
    <div id="alias-explore-wrap" class="col-span-2 overflow-y-auto max-h-screen m-2 px-2">
      <div class="flex flex-col gap-4">
        <h1 class="text-lg font-semibold text-slate-800 dark:text-slate-100">Alias Explorer</h1>
        <div class="grid grid-cols-3 gap-2">
          {@card["aliases"]}
        </div>
      </div>
    </div>
    """
  end

  defp extract(:all, {_, am} = as) do
    aliases =
      am
      |> Map.to_list()
      |> Enum.sort_by(fn {_a, n} -> String.downcase(n) end)
      |> to_links(as)

    %{"aliases" => aliases}
  end

  defp extract(_, _), do: :none

  defp to_links(aliases, as) do
    aliases
    |> Enum.map(fn {a, _} ->
      {:safe, html} = Display.linked_author(a, as)

      "<div class=\"rounded-lg border border-slate-200 dark:border-slate-700 p-2 flex items-center gap-2 hover:border-amber-500 dark:hover:border-amber-400 transition-colors\">" <>
        html <> "</div>"
    end)
    |> Phoenix.HTML.raw()
  end
end
