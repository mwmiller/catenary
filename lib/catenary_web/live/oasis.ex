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
       connect_mode: Map.get(assigns, :connect_mode, "announced"),
       manual: Map.get(assigns, :manual, %{}),
       mdns_peers: Map.get(assigns, :mdns_peers, []),
       bootstrap: Map.fetch!(assigns, :bootstrap)
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
              {tab_title(@connect_mode)}
            </h1>
          </div>
          <div
            class="flex items-center rounded-md border border-slate-200 dark:border-slate-700 text-xs font-mono"
            role="group"
            aria-label="Connection source"
          >
            <button
              class={[
                mode_tab(@connect_mode == "announced"),
                "px-2 py-0.5 rounded-l-md transition-colors cursor-pointer"
              ]}
              phx-click="set-connect-mode"
              value="announced"
              type="button"
              title="Show announced oases"
            >
              ✦
            </button>
            <span class="w-px bg-slate-200 dark:bg-slate-700 self-stretch" aria-hidden="true"></span>
            <button
              class={[
                mode_tab(@connect_mode == "peers"),
                "px-2 py-0.5 rounded-r-md transition-colors cursor-pointer"
              ]}
              phx-click="set-connect-mode"
              value="peers"
              type="button"
              title="Discover and connect to peers"
            >
              ⌖
            </button>
          </div>
        </div>

        <%= case @connect_mode do %>
          <% "peers" -> %>
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
            <div class="flex items-center gap-2">
              <button
                phx-click="browse-mdns"
                class="font-mono text-xs px-2 py-0.5 rounded border border-slate-200 dark:border-slate-700 text-slate-600 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors cursor-pointer"
                type="button"
                title="Scan for local peers"
              >
                ↻
              </button>
              <span class="font-mono text-[10px] text-slate-400 dark:text-slate-500">
                Local network
              </span>
            </div>
            <%= if peer_rows(@mdns_peers, @manual) == [] do %>
              <div class="font-mono text-xs rounded-lg border border-slate-200 dark:border-slate-700 p-3 text-slate-600 dark:text-slate-300">
                <span class="text-slate-400 dark:text-slate-500">∅</span>
              </div>
            <% else %>
              <div class="font-mono text-xs flex flex-col divide-y divide-slate-200 dark:divide-slate-700">
                <%= for {row, _index} <- Enum.with_index(peer_rows(@mdns_peers, @manual)) do %>
                  <div class="flex items-center gap-2 py-2">
                    <div class="flex-none text-slate-400 dark:text-slate-500" title={row.title}>
                      {row.icon}
                    </div>
                    <%= if owner = row[:owner] do %>
                      <div class="flex-auto min-w-0">
                        <div class="text-slate-800 dark:text-slate-100">
                          {Phoenix.HTML.raw(Display.linked_author(owner, @aliases))}
                        </div>
                        <div class="text-slate-400 dark:text-slate-500 text-[10px]">
                          {row.subtitle}
                        </div>
                      </div>
                    <% else %>
                      <div class="flex-auto min-w-0">
                        <div class="text-slate-800 dark:text-slate-100">
                          {row.title}
                        </div>
                        <div class="text-slate-400 dark:text-slate-500 text-[10px]">
                          {row.subtitle}
                        </div>
                      </div>
                    <% end %>
                    <%= if entry = row[:entry] do %>
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
                    <% else %>
                      <button
                        class="px-1.5 py-0.5 rounded text-amber-800 dark:text-amber-300 hover:bg-amber-50 dark:hover:bg-amber-900/40 transition-colors"
                        phx-click="connect-mdns"
                        phx-disable-with="↯"
                        phx-value-ip={to_string(:inet.ntoa(row.ip))}
                        phx-value-port={row.port}
                        title="Connect to peer"
                      >
                        ⇆
                      </button>
                    <% end %>
                    <%= if owner = row[:owner] do %>
                      <div class="flex-none">
                        {Phoenix.HTML.raw(Display.scaled_avatar(owner, 2, ["m-1", "align-middle"]))}
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>

          <% _ -> %>
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
                        Phoenix.HTML.raw(Display.scaled_avatar(op, 2, ["shrink-0"]))
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

  defp tab_title("peers"), do: "Peers"
  defp tab_title(_), do: "Oasis Explorer"

  defp mode_tab(true), do: "bg-amber-500/20 text-amber-800 dark:text-amber-300"

  defp mode_tab(false),
    do: "text-slate-500 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800"

  # The peers tab merges mDNS peers and manual {host, port} targets into one
  # list. Each mDNS peer carries its owner (base62 key, if announced) alongside
  # the instance name and IP address; a manual target is matched by its
  # {host, port} key so a target already discovered over mDNS is shown once,
  # with its live lifecycle state (the DNS name vs IP may differ, so an mDNS
  # peer row can still carry a connect button even while a manual entry lives
  # under a different host spelling).
  defp peer_rows(mdns_peers, manual) do
    mdns_hosts = MapSet.new(mdns_peers, fn peer -> peer_host_key(peer) end)

    mdns_rows =
      Enum.map(mdns_peers, fn peer ->
        %{
          kind: :mdns,
          ip: peer.ip,
          port: peer.port,
          host_key: peer_host_key(peer),
          host: to_string(:inet.ntoa(peer.ip)),
          title: peer_title(peer),
          subtitle: peer_subtitle(peer),
          owner: peer_owner(peer),
          icon: "☰",
          entry: manual[peer_host_key(peer)]
        }
      end)

    manual_rows =
      manual
      |> Enum.reject(fn {key, _entry} -> MapSet.member?(mdns_hosts, key) end)
      |> Enum.map(fn {{host, port}, entry} ->
        %{
          kind: :manual,
          ip: nil,
          port: port,
          host_key: {host, port},
          host: host,
          title: "#{host}:#{port}",
          subtitle: nil,
          owner: nil,
          icon: "⌖",
          entry: entry
        }
      end)

    mdns_rows ++ manual_rows
  end

  defp peer_host_key(peer), do: {to_string(:inet.ntoa(peer.ip)), peer.port}

  defp peer_host(peer), do: to_string(:inet.ntoa(peer.ip))

  defp peer_title(peer) do
    peer[:instance] || "#{peer_host(peer)}:#{peer.port}"
  end

  defp peer_subtitle(peer) do
    case peer[:instance] do
      nil -> nil
      _ -> "#{peer_host(peer)}:#{peer.port}"
    end
  end

  defp peer_owner(peer) do
    case peer.txt["owner"] do
      owner when owner in [nil, ""] -> nil
      owner -> owner
    end
  end
end
