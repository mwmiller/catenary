defmodule Catenary.Live.IdentityManager do
  use Phoenix.LiveComponent
  use Phoenix.HTML
  alias CatenaryWeb.Router.Helpers, as: Routes

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, Map.merge(assigns, %{identities: Baobab.identities()}))}
  end

  @impl true
  def render(assigns) do
    ~L"""
      <div class="min-w-full font-sans row-span-full">
        <h1 class="text=center">Identity Manager</h1>
        <hr/>
        <div class="grid grid-cols-2 mt-10">
          <%= for {n, k} <- @identities do %>
            <div><img src="<%= Catenary.identicon(k, 8) %>">
              Name: <%= n %><br/>
              AKA: <%= Catenary.short_id(k) %><br/>
              Activity: <%= log_info_string(@store, k) %><br/>
              Keys:
             <%= form_tag(Routes.export_path(@socket, :create)) %>
              <input type="hidden" value="<%= n %>" name="whom"/>
              <%= submit "Export", class: "btn btn-secondary w-full" %>
            </form>
            </div>
          <% end %>
      </div>
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
