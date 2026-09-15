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
    <div id="alias-explore-wrap" class="content-wrap">
      <div class="flex flex-col gap-4">
        <h1 class="text-lg font-semibold text-slate-800 dark:text-slate-100">Alias Explorer</h1>
        <div :if={@card["aliases"] == ""} class="text-sm text-slate-400 dark:text-slate-500">
          No alias messages.
        </div>
        <div :if={@card["aliases"] != ""} class="grid grid-cols-3 gap-2">
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

    content =
      case aliases do
        [] -> ""
        _ -> to_links(aliases, as)
      end

    %{"aliases" => content}
  end

  defp extract(_, _), do: :none

  defp to_links(aliases, as) do
    aliases
    |> Enum.map(fn {a, _} ->
      {:safe, ava} = Display.scaled_avatar(a, 2, ["shrink-0", "rounded-full"])
      {:safe, html} = Display.linked_author(a, as)

      "<div class=\"rounded-lg border border-transparent p-2 flex items-center gap-2 hover:border-amber-500 dark:hover:border-amber-400 transition-colors\">" <>
        ava <> html <> "</div>"
    end)
    |> Phoenix.HTML.raw()
  end
end
