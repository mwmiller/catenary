defmodule Catenary.Live.IdentityManager do
  use Phoenix.LiveComponent
  use Phoenix.HTML

  @impl true
  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  @impl true
  def render(assigns) do
    ~L"""
     <div id="identview-wrap" class="col-span-full overflow-y-auto max-h-screen m-2 p-x-2">
      <div class="my-5 text-center min-w-full"><%= Catenary.entry_icon_link({@identity,-1,0}, 8) |> Phoenix.HTML.raw()  %></div>
      <form method="post" id="identity-form" phx-change="identity-change">
      <table class="min-w-full"><thead>
        <tr class="border border-slate-200 dark:border-slate-800"><th>Selection</th><th>Name</th><th>Identicon</th><th>AKA</th><th>Activity</th></tr>
      </thead>
      <tbody class="text-center">
        <%= for {n, k} <- @identities do %>
          <tr class="my-10 border <%= if k == @identity, do: "bg-emerald-100 border-emerald-200 dark:bg-cyan-800 dark:border-cyan-900", else: "border-slate-200 dark:border-slate-800" %>">
            <td class="py-5"><input type="radio" name="selection" value="<%= n %>" <%= if k == @identity, do: "checked" %>></td>
            <td><input class="bg-white dark:bg-black" type="text" size=16 id="<%= n %>" value="<%= n %>" phx-blur="rename-id-<%= n %>" /></td>
            <td><img class="mx-auto" src="<%= Catenary.identicon(k, 4) %>"></td>
            <td><%= Catenary.linked_author(k) %></td>
            <td><%= log_info_string(@store, k) %></td>
          </tr>
        <% end %>
        <tr class="my-10 border border-slate-200 dark:border-slate-800">
          <td class="py=5">&nbsp;</td>
          <td><input class="bg-white dark:bg-black" type="text" size=16 id="new-id" phx-blur="new-id" /></td>
          <td>&nbsp;</td>
          <td>&nbsp;</td>
          <td>none yet</td>
        </tr>
      </tbody>
    </table>
    </form>
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
