defmodule Catenary.Live.OasisExplorer do
  @moduledoc """
  LiveComponent rendering an oasis entry card (running peer nodes).
  """
  use Phoenix.LiveComponent
  alias Catenary.Display

  @impl true
  def update(assigns, socket) do
    {:ok, nodes} = assigns.oases

    {:ok,
     assign(socket,
       aliases: assigns.aliases,
       nodes: nodes,
       opened: assigns.opened
     )}
  end

  @impl true

  def render(%{nodes: []} = assigns) do
    ~H"""
    <div id="oasis-explore-wrap" class="content-wrap">
      <div class="flex flex-col gap-4">
        <div class="flex items-center justify-between gap-3">
          <h1 class="text-lg font-semibold text-slate-800 dark:text-slate-100">Oasis Explorer</h1>
          <button
            class="px-1.5 py-0.5 rounded text-slate-400 dark:text-slate-500 hover:text-slate-600 dark:hover:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors text-sm"
            phx-click="clear-oases"
            phx-disable-with="↯"
            title="Clear oases"
          >
            ✕
          </button>
        </div>
        <div class="font-mono text-xs rounded-lg border border-slate-200 dark:border-slate-700 p-3 text-slate-600 dark:text-slate-300">
          No recent oases found.
          <%= if @opened == 0 do %>
            <button
              class="ml-1 text-amber-800 dark:text-amber-300 hover:text-amber-600 dark:hover:text-amber-200"
              phx-click="init-connect"
              phx-disable-with="↯ trying ↯"
              title="Connect to bootstrap node"
            >
              ⇆ try bootstrap node ⇆
            </button>
          <% else %>
            ⥀ attempting sync ⥀
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div id="oasisexplore-wrap" class="content-wrap">
      <div class="flex flex-col gap-4">
        <div class="flex items-center justify-between gap-3">
          <h1 class="text-lg font-semibold text-slate-800 dark:text-slate-100">Oasis Explorer</h1>
          <button
            class="px-1.5 py-0.5 rounded text-slate-400 dark:text-slate-500 hover:text-slate-600 dark:hover:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors text-sm"
            phx-click="clear-oases"
            phx-disable-with="↯"
            title="Clear oases"
          >
            ✕
          </button>
        </div>
        <div class="font-mono text-xs flex flex-col divide-y divide-slate-200 dark:divide-slate-700">
          <%= for recent <- @nodes do %>
            <div class="flex items-center gap-2 py-2">
              <div class="flex-none">
                {if op = recent["operator"] do
                  Phoenix.HTML.raw(Display.scaled_avatar(op, 1, ["m-1", "align-middle"]))
                end}
              </div>
              <div class="flex-auto min-w-0">
                <span class="text-slate-800 dark:text-slate-100">{recent["name"]}</span>
                <span class="text-slate-400 dark:text-slate-500">
                  ({Phoenix.HTML.raw(Display.linked_author(elem(recent.id, 0), @aliases))})
                </span>
              </div>
              <%= if recent.connected do %>
                <span class="text-emerald-600 dark:text-emerald-400" title="Connected">⥀</span>
              <% else %>
                <button
                  class="px-1.5 py-0.5 rounded text-amber-800 dark:text-amber-300 hover:bg-amber-50 dark:hover:bg-amber-900/40 transition-colors"
                  phx-click="connect"
                  phx-disable-with="↯"
                  value={Catenary.index_to_string(recent.id)}
                  title="Connect to oasis"
                >
                  ⇆
                </button>
              <% end %>
              <div class="flex-none">
                {Phoenix.HTML.raw(
                  Display.scaled_avatar(elem(recent.id, 0), 2, ["m-1", "align-middle"])
                )}
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
