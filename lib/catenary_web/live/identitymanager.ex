defmodule Catenary.Live.IdentityManager do
  use Phoenix.LiveComponent
  use Phoenix.HTML

  @impl true
  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  @impl true
  def render(assigns) do
    ~L"""
     <div id="identview-wrap" class="col-span-full overflow-y-auto max-h-screen m-2 p-x-2">
      <h1 class="text-center">Identity Manager</h1>
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
            <td><button phx-click="view-entry" value="<%= Catenary.index_to_string({k,0,0}) %>"><%= log_info_string(@store, k) %></a></td>
          </tr>
        <% end %>
        <tr class="my-10 border border-slate-200 dark:border-slate-800">
          <td class="py=5">&nbsp;</td>
          <td><input class="bg-white dark:bg-black" type="text" size=16 id="new-id" phx-blur="new-id" /></td>
          <td>&nbsp;</td>
          <td>&nbsp;</td>
          <td>None.</td>
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

    Integer.to_string(entries) <>
      " entries across " <> Integer.to_string(Enum.count(logs)) <> " logs"
  end
end
