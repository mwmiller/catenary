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
       opened: assigns.opened,
       connect_open: Map.get(assigns, :connect_open, false),
       manual: Map.get(assigns, :manual, %{}),
       bootstrap: Map.get(assigns, :bootstrap, QuaggaDef.bootstrap_node())
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="oasisexplore-wrap" class="content-wrap">
      <div class="flex flex-col gap-4">
        <div class="flex items-center justify-between gap-3">
          <div class="flex items-center gap-2 min-w-0">
            <h1 class="text-lg font-semibold text-slate-800 dark:text-slate-100 truncate">
              {if @connect_open, do: "Manual Connect", else: "Oasis Explorer"}
            </h1>
          </div>
          <div
            class="flex items-center rounded-md border border-slate-200 dark:border-slate-700 text-xs font-mono"
            role="group"
            aria-label="Connection source"
          >
            <button
              class={[
                mode_tab_color(not @connect_open),
                "px-2 py-0.5 rounded-l-md transition-colors cursor-pointer"
              ]}
              phx-click="set-connect-mode"
              value="announced"
              type="button"
              title="Show announced oases"
            >
              ◉
            </button>
            <span class="w-px bg-slate-200 dark:bg-slate-700 self-stretch" aria-hidden="true"></span>
            <button
              class={[
                mode_tab_color(@connect_open),
                "px-2 py-0.5 rounded-r-md transition-colors cursor-pointer"
              ]}
              phx-click="set-connect-mode"
              value="manual"
              type="button"
              title="Connect to a peer by host:port"
            >
              ⌖
            </button>
          </div>
        </div>

        <%= if @connect_open do %>
          <form
            phx-submit="connect-manual"
            class="font-mono text-xs rounded-lg border border-slate-200 dark:border-slate-700 p-3 flex flex-col gap-3"
            autocomplete="off"
          >
            <div class="flex items-center gap-2 py-2">
              <div class="flex-none text-slate-400 dark:text-slate-500" title="Manual peer">
                ⌖
              </div>
              <div class="flex-auto min-w-0 flex items-center gap-2">
                <input
                  type="text"
                  name="host"
                  placeholder="host"
                  aria-label="Host"
                  value={elem(@bootstrap, 0)}
                  class="flex-1 min-w-0 rounded-md border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800 px-2 py-1 text-sm text-slate-500 dark:text-slate-400 placeholder:text-slate-400 dark:placeholder:text-slate-500"
                />
                <span class="text-slate-400 dark:text-slate-500">:</span>
                <input
                  type="text"
                  name="port"
                  placeholder="port"
                  aria-label="Port"
                  value={elem(@bootstrap, 1) |> Integer.to_string()}
                  class="w-20 rounded-md border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800 px-2 py-1 text-sm text-slate-500 dark:text-slate-400 placeholder:text-slate-400 dark:placeholder:text-slate-500"
                />
              </div>
              <div class="flex-none">
                <button
                  type="submit"
                  class="px-1.5 py-0.5 rounded text-amber-800 dark:text-amber-300 hover:bg-amber-50 dark:hover:bg-amber-900/40 transition-colors"
                  phx-disable-with="↯"
                  title="Connect to peer"
                >
                  ⇆
                </button>
              </div>
            </div>
          </form>
          <%= if map_size(@manual) > 0 do %>
            <div class="font-mono text-xs flex flex-col divide-y divide-slate-200 dark:divide-slate-700">
              <%= for {{host, port}, entry} <- @manual do %>
                <div class="flex items-center gap-2 py-2">
                  <div class="flex-none text-slate-400 dark:text-slate-500" title="Manual peer">
                    ⌖
                  </div>
                  <div class="flex-auto min-w-0">
                    <span class="text-slate-800 dark:text-slate-100">{host}:{port}</span>
                  </div>
                  <%= case entry.state do %>
                    <% :connected -> %>
                      <span class="text-emerald-600 dark:text-emerald-400" title="Connected">⥀</span>
                    <% :connecting -> %>
                      <span
                        class="text-amber-800 dark:text-amber-300 animate-pulse"
                        title="Connecting"
                      >
                        ↯
                      </span>
                    <% :failed -> %>
                      <span class="text-rose-600 dark:text-rose-400" title="Connection failed">⛒</span>
                    <% _ -> %>
                      <span class="text-slate-400 dark:text-slate-500" title="Attempting sync">⥀</span>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        <% else %>
          <%= if @nodes == [] do %>
            <div class="font-mono text-xs rounded-lg border border-slate-200 dark:border-slate-700 p-3 text-slate-600 dark:text-slate-300">
              <span class="text-slate-400 dark:text-slate-500" title="No recent oases">∅</span>
              <%= if @opened > 0 do %>
                <span class="ml-1 text-slate-400 dark:text-slate-500" title="Attempting sync">
                  ⥀
                </span>
              <% end %>
            </div>
          <% else %>
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
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp mode_tab_color(true), do: "bg-amber-500/20 text-amber-800 dark:text-amber-300"

  defp mode_tab_color(false),
    do: "text-slate-500 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800"
end
