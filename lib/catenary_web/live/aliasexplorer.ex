defmodule Catenary.Live.AliasExplorer do
  @moduledoc """
  LiveComponent rendering an explorer for an alias entry.
  """
  use Phoenix.LiveComponent
  alias Catenary.Display

  @impl true
  def update(%{entry: which, aliases: aliases} = assigns, socket) do
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
      {:safe, ava} = Display.scaled_avatar(a, 2, ["shrink-0"])
      entry_str = Catenary.index_to_string({:profile, a})

      ~s(<button value="#{entry_str}" phx-click="view-entry" class="block w-full text-left rounded-lg border border-transparent p-2 flex items-center gap-2 hover:border-amber-500 dark:hover:border-amber-400 transition-colors">) <>
        ava <>
        ~s(<span class="text-sm text-slate-700 dark:text-slate-300">) <>
        Catenary.Display.short_id(a, as) <>
        ~s(</span></button>)
    end)
    |> Phoenix.HTML.raw()
  end

  @impl true
  def handle_event("view-entry" = event, payload, socket) do
    send(socket.parent_pid, {__MODULE__, event, payload})
    {:noreply, socket}
  end
end
