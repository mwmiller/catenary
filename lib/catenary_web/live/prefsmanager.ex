defmodule Catenary.Live.PrefsManager do
  use Phoenix.LiveComponent
  use Phoenix.HTML
  alias Catenary.Display

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, Map.merge(assigns, %{:blocked => blocked_map_set(assigns.clump_id)}))}
  end

  @impl true
  def render(assigns) do
    {ac, lc, ec} = Catenary.clump_stats(assigns.clump_id)

    ~L"""
     <div id="identview-wrap" class="col-span-full overflow-y-auto max-h-screen m-2 p-x-2">
       <div class="my-2 text-center min-w-full"><a href="/authors/<%= @identity %>"><%= Display.scaled_avatar(@identity, 8, ["mx-auto"])  %></a></div>
      <form method="post" id="clump-form" phx-change="clump-change">
        <label for"clump_id">🎋</label>
        <select name="clump_id" class="bg-white dark:bg-black">
          <%= for {c,_} <- @clumps do %>
            <option value="<%= c %>" <%= if c == @clump_id, do: "selected" %>><%= c %></option>
          <% end %>
        </select>
      </form>
      <p class="m-1 text-xs"><%= ec %> log entries available across <%= lc %> logs from <%= ac %> authors in <%= @clump_id %>.</p>
      <form method="post" id="identity-form" phx-change="identity-change">
      <table class="min-w-full"><thead>
        <thead>
          <tr class="border border-slate-200 dark:border-slate-800"><th>Select</th><th>Name</th><th>Avatar</th><th>AKA</th><th>Activity</th><th class="text-amber-900">DROP</th></tr>
      </thead>
      <tbody class="text-center">
        <%= for {n, k} <- @identities do %>
          <tr class="my-10 border <%= if k == @identity, do: "bg-slate-300 border-stone-400 dark:bg-stone-600 dark:border-slate-900", else: "border-slate-200 dark:border-slate-800" %>">
            <td class="py-5"><input type="radio" name="selection" value="<%= n %>" <%= if k == @identity, do: "checked" %>></td>
            <td><input class="bg-white dark:bg-black" type="text" size=16 id="<%= n %>" value="<%= n %>" phx-blur="rename-id-<%= n %>" /></td>
            <td><%= Display.scaled_avatar(k, 4, ["mx-auto"])  %></td>
            <td><%= Display.linked_author(k, @aliases, :href) %></td>
            <td><%= log_info_string(@store, k) %></td>
            <td> <%= if k == @identity do %>⛒<% else %><input type="radio" name="drop" value="<%= n %>"><% end %></td>
          </tr>
        <% end %>
        <tr class="my-10 border border-slate-200 dark:border-slate-800">
          <td class="py=5">&nbsp;</td>
          <td><input class="bg-white dark:bg-black" type="text" size=16 id="new-id" phx-blur="new-id" /></td>
          <td>&nbsp;</td>
          <td>&nbsp;</td>
          <td>none yet</td>
          <td>⛒</td>
        </tr>
      </tbody>
    </table>
    <label for="facet_id">❖</label>
    <input class="bg-white dark:bg-black m-5" phx-blur="facet-change" type="numeric" name="facet_id" size=3 value="<%= @facet_id %>">
    </form>
    </div>
      <div>Preferences
      <form method="post" id="pref-form" phx-change="prefs-change">
      <input class="bg-white dark:bg-black" type="checkbox"  name="automention" <%= if Catenary.Preferences.get(:automention), do: "checked" %> > Auto-mention
      <input class="bg-white dark:bg-black" type="checkbox"  name="autosync" <%= if Catenary.Preferences.get(:autosync), do: "checked" %> > Auto-sync
      </form>
      </div>
      <div class="flex-1 min-w-full">
          <div>Accept log types</div>
      <form method="post" id="accept-form" phx-submit="new-entry">
        <input type="hidden" name="log_id" value="1337">
        <input type="hidden" name="listed" value="accept">
        <div class="grid grid-cols-3">
          <%= for {s, a} <- Display.all_pretty_log_pairs do %>
            <div><%= log_accept_input(a, @blocked) |> Phoenix.HTML.raw %>&nbsp;<%= s %> </div>
          <% end %>
    </div>
        <%= Display.log_submit_button %>
      </form>
    </div>
    </div>
    <div class="flex flex-row min-w-full">
      <div class="flex-auto"><button class="border opacity-61 p-2 m-10 bg-stone-200 dark:bg-stone-800" value="all" phx-disable-with="⌘⌘⌘" phx-click="shown">catch up</button></div>
      <div class="flex-auto"><button class="border opacity-61 p-2 m-10 bg-stone-200 dark:bg-stone-800" value="none" phx-disable-with="⎚⎚⎚"  phx-click="shown">start fresh</button></div>
      <div class="flex-auto"><button class="border opacity-61 p-2 m-10 bg-stone-200 dark:bg-stone-800" value="all" phx-disable-with="〆〆〆"  phx-click="compact">compact logs</button></div>
    """
  end

  defp log_accept_input(:graph, _blocked),
    do: "☑︎ <input type=\"hidden\" name=\"log_name-graph\" value=\"graph\">"

  defp log_accept_input(name, blocked) do
    logs = QuaggaDef.logs_for_name(name) |> MapSet.new()
    # We'll assume that if any one is blocked we meant 
    # to block them all.
    checked =
      case MapSet.intersection(blocked, logs) |> Enum.count() do
        0 -> " checked "
        _ -> ""
      end

    ln = Atom.to_string(name)

    "<input class=\"bg-white dark:bg-black\" type=\"checkbox\"  name=\"log_name-" <>
      ln <> "\" value=\"" <> ln <> "\"" <> checked <> "/>"
  end

  defp blocked_map_set(clump_id) do
    clump_id |> Baobab.ClumpMeta.blocks_list() |> MapSet.new()
  end

  defp log_info_string(store, k) do
    logs = store |> Enum.filter(fn {a, _, _} -> a == k end)
    entries = logs |> Enum.reduce(0, fn {_, _, e}, a -> a + e end)

    humane_count(entries) <> " entries across " <> humane_count(logs) <> " logs"
  end

  defp humane_count(flt) when is_float(flt), do: humane_count(trunc(flt))
  defp humane_count(list) when is_list(list), do: humane_count(length(list))

  defp humane_count(str) when is_binary(str) do
    amt =
      try do
        String.to_integer(str)
      rescue
        _ -> String.length(str)
      end

    humane_count(amt)
  end

  defp humane_count(0), do: "no"
  defp humane_count(e) when e < 3, do: "a couple"
  defp humane_count(e) when e < 5, do: "a few"
  defp humane_count(e) when e < 10, do: "several"
  defp humane_count(e) when e < 144, do: "dozens of"
  defp humane_count(e) when e < 451, do: "hundreds of"
  defp humane_count(e) when is_integer(e), do: "very many"
  defp humane_count(_), do: "‽"
end
