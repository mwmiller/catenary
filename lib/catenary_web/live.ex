defmodule CatenaryWeb.Live do
  use CatenaryWeb, :live_view

  # Every 9s or so, we see if someone put new stuff in the store
  @store_refresh 9001

  def mount(_params, _session, socket) do
    starting_sort = [dir: :dec, by: :seq]
    # Making sure these exist, but also faux docs
    [:asc, :dec, :author, :logid, :seq]

    {store, watering} =
      case connected?(socket) do
        true ->
          Process.send_after(self(), :check_store, @store_refresh, [])
          si = Baobab.stored_info()
          {sorted_store(si, starting_sort), watering(si)}

        false ->
          {[], []}
      end

    opts = [store: store, watering: watering, sorter: starting_sort]

    {:ok, assign(socket, opts)}
  end

  def render(assigns) do
    ~L"""
    <section class="phx-hero" id="page-live">
    <div class="mx-2 grid grid-cols-1 md:grid-cols-2 gap-10 justify-center font-mono">
      <div>
        <%= for {recent, index}  <- Enum.with_index(@watering) do %>
          <div class="<%= case rem(index, 2)  do
         0 ->  "bg-emerald-200 dark:bg-cyan-700"
          1 -> "bg-emerald-400 dark:bg-sky-700"
        end %>"><%= recent["name"] %><br><%= recent["host"]<>":"<>Integer.to_string(recent["port"]) %></div>
        <% end %>
      </div>
      <div>
       <table "table-auto m-5 width='100%'">
         <tr>
           <th><button value="asc-author" phx-click="sort">↓</button> Author <button value="dec-author" phx-click="sort">↑</button></th>
           <th><button value="asc-logid" phx-click="sort">↓</button> Log Id <button value="dec-logid" phx-click="sort">↑</button></th>
           <th><button value="asc-seq" phx-click="sort">↓</button> Max Seq <button value="dec-seq" phx-click="sort">↑</button></th>
         </tr>
         <%= for {author, log_id, seq} <- @store do %>
         <tr><td><%= String.slice(author, 0..15) %></td><td><%= log_id %></td><td><%= seq %></td></tr>
         <% end %>
      </table>
    </div>
    </div>
    """
  end

  def handle_event("sort", %{"value" => <<dir::binary-size(3), "-", by::binary>>}, socket) do
    sorter = [dir: String.to_existing_atom(dir), by: String.to_existing_atom(by)]
    {:noreply, assign(socket, store: sorted_store(socket.assigns.store, sorter), sorter: sorter)}
  end

  def handle_info(:check_store, socket) do
    Process.send_after(self(), :check_store, @store_refresh)

    {:noreply, assign(socket, store: Baobab.stored_info() |> sorted_store(socket.assigns.sorter))}
  end

  defp watering(store) do
    store
    |> Enum.filter(fn {_, l, _} -> l == 8483 end)
    |> extract_recents(DateTime.now!("Etc/UTC"), [])
  end

  defp extract_recents([], _, acc), do: acc

  defp extract_recents([{a, l, e} | rest], now, acc) do
    try do
      %Baobab.Entry{payload: payload} = Baobab.log_entry(a, e, log_id: l)
      {:ok, map, ""} = CBOR.decode(payload)

      case map do
        %{"running" => ts} ->
          {:ok, then, _offset} = DateTime.from_iso8601(ts)
          sago = DateTime.diff(then, now)

          cond do
            sago > -172_800 -> extract_recents(rest, now, [map | acc])
            true -> extract_recents(rest, now, acc)
          end

        _ ->
          extract_recents(rest, now, acc)
      end
    rescue
      _ -> extract_recents(rest, now, acc)
    end
  end

  defp sorted_store(store, opts) do
    elem =
      case Keyword.get(opts, :by) do
        :author -> fn {a, _, _} -> a end
        :logid -> fn {_, l, _} -> l end
        :seq -> fn {_, _, s} -> s end
      end

    comp =
      case Keyword.get(opts, :dir) do
        :asc -> &Kernel.<=/2
        :dec -> &Kernel.>=/2
      end

    # The extra step keeps it stable across
    # refresh from stored_info which is in the
    # described order [dir: :asc, by: author]
    # We also filter out Baby annoucement logs because
    # We're using them differently
    # If this ever becomes more than POC and a botleneck, yay!
    store
    |> Enum.reject(fn {_, l, _} -> l == 8483 end)
    |> Enum.sort_by(fn {a, _, _} -> a end, &Kernel.<=/2)
    |> Enum.sort_by(elem, comp)
  end
end
