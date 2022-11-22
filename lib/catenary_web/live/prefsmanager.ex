defmodule Catenary.Live.PrefsManager do
  use Phoenix.LiveComponent
  use Phoenix.HTML

  @impl true
  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  @impl true
  def render(assigns) do
    ~L"""
     <div id="identview-wrap" class="col-span-full overflow-y-auto max-h-screen m-2 p-x-2">
       <div class="my-5 text-center min-w-full"><a href="/authors/<%= @identity %>"><img class="mx-auto" src="<%= Catenary.identicon(@identity, 8) %>"></a></div>
      <form method="post" id="clump-form" phx-change="clump-change">
        <label for"clump_id">🎋</label>
        <select name="clump_id" class="m-10 bg-white dark:bg-black">
          <%= for {c,_} <- @clumps do %>
            <option value="<%= c %>" <%= if c == @clump_id, do: "selected" %>><%= c %></option>
          <% end %>
        </select>
      </form>
      <form method="post" id="identity-form" phx-change="identity-change">
      <table class="min-w-full"><thead>
        <thead>
          <tr class="border border-slate-200 dark:border-slate-800"><th>Select</th><th>Name</th><th>Identicon</th><th>AKA</th><th>Activity</th><th class="text-amber-900">DROP</th></tr>
      </thead>
      <tbody class="text-center">
        <%= for {n, k} <- @identities do %>
          <tr class="my-10 border <%= if k == @identity, do: "bg-slate-300 border-stone-400 dark:bg-stone-600 dark:border-slate-900", else: "border-slate-200 dark:border-slate-800" %>">
            <td class="py-5"><input type="radio" name="selection" value="<%= n %>" <%= if k == @identity, do: "checked" %>></td>
            <td><input class="bg-white dark:bg-black" type="text" size=16 id="<%= n %>" value="<%= n %>" phx-blur="rename-id-<%= n %>" /></td>
            <td><img class="mx-auto" src="<%= Catenary.identicon(k, 4) %>"></td>
            <td><%= Catenary.linked_author(k, @aliases) %></td>
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
    <div class="flex flex-row min-w-full">
      <div class="flex-auto"><button class="border opacity-61 p-2 m-10 bg-stone-200 dark:bg-stone-800" value="all" phx-disable-with="⌘⌘⌘" phx-click="shown">catch up</button></div>
      <div class="flex-auto"><button class="border opacity-61 p-2 m-10 bg-stone-200 dark:bg-stone-800" value="none" phx-disable-with="⎚⎚⎚"  phx-click="shown">start fresh</button></div>
      <div class="flex-auto"><button class="border opacity-61 p-2 m-10 bg-stone-200 dark:bg-stone-800" value="all" phx-disable-with="〆〆〆"  phx-click="compact">compact logs</button></div>
    </div>
    """
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
