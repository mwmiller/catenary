defmodule CatenaryWeb.Live do
  use CatenaryWeb, :live_view

  # Every 9s or so, we see if someone put new stuff in the store
  @store_refresh 9001

  def mount(_params, _session, socket) do
    starting_sort = [dir: :dec, by: :seq]

    store =
      case connected?(socket) do
        true ->
          Process.send_after(self(), :check_store, @store_refresh, [])
          Baobab.stored_info()

        false ->
          []
      end
      |> sorted_store(starting_sort)

    opts = [store: store, sorter: starting_sort]

    {:ok, assign(socket, opts)}
  end

  def render(assigns) do
    ~L"""
    <section class="phx-hero" id="page-live">
    <div class="mx-2 grid grid-cols-1 md:grid-cols-4 gap-10 justify-center font-mono">
      <h1>Catenary</h1>
       <table class="my-4">
         <tr>
           <th><button phx-click="asc_author">↓</button> Author <button phx-click="dec_author">↑</button></th>
           <th><button phx-click="asc_logid">↓</button> Log Id <button phx-click="dec_logid">↑</button></th>
           <th><button phx-click="asc_seq">↓</button> Max Seq <button phx-click="dec_seq">↑</button></th>
         </tr>
         <%= for {author, log_id, seq} <- @store do %>
         <tr><td><%= String.slice(author, 0..15) %></td><td><%= log_id %></td><td><%= seq %></td></tr>
         <% end %>
      </table>
    </div>
    """
  end

  def handle_event("asc_author", _value, socket) do
    sorter = [dir: :asc, by: :author]
    {:noreply, assign(socket, store: sorted_store(socket.assigns.store, sorter), sorter: sorter)}
  end

  def handle_event("dec_author", _value, socket) do
    sorter = [dir: :dec, by: :author]
    {:noreply, assign(socket, store: sorted_store(socket.assigns.store, sorter), sorter: sorter)}
  end

  def handle_event("asc_logid", _value, socket) do
    sorter = [dir: :asc, by: :logid]
    {:noreply, assign(socket, store: sorted_store(socket.assigns.store, sorter), sorter: sorter)}
  end

  def handle_event("dec_logid", _value, socket) do
    sorter = [dir: :dec, by: :logid]
    {:noreply, assign(socket, store: sorted_store(socket.assigns.store, sorter), sorter: sorter)}
  end

  def handle_event("asc_seq", _value, socket) do
    sorter = [dir: :asc, by: :seq]
    {:noreply, assign(socket, store: sorted_store(socket.assigns.store, sorter), sorter: sorter)}
  end

  def handle_event("dec_seq", _value, socket) do
    sorter = [dir: :dec, by: :seq]
    {:noreply, assign(socket, store: sorted_store(socket.assigns.store, sorter), sorter: sorter)}
  end

  def handle_info(:check_store, socket) do
    Process.send_after(self(), :check_store, @store_refresh)

    {:noreply, assign(socket, store: Baobab.stored_info() |> sorted_store(socket.assigns.sorter))}
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
    # If this ever becomes more than POC and a botleneck, yay!
    store
    |> Enum.sort_by(fn {a, _, _} -> a end, &Kernel.<=/2)
    |> Enum.sort_by(elem, comp)
  end
end
