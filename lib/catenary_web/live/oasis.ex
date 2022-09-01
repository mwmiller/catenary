defmodule Catenary.Live.OasisBox do
  use Phoenix.LiveComponent
  @impl true
  def render(assigns) do
    ~L"""
    <div>
      <%= for {recent, index}  <- Enum.with_index(@watering) do %>
        <div title="<%= Timex.Format.DateTime.Formatters.Relative.format!(recent["running"], "as of {relative}")%>" class="m-2 <%= case rem(index, 2)  do
        0 ->  "bg-emerald-200 dark:bg-cyan-700"
        1 -> "bg-emerald-400 dark:bg-sky-700"
      end %>"> <img class="m-1 float-right align-middle" src="<%= Catenary.identicon(recent.id, @iconset)%>">
        <%= recent["name"] %> (<%= Catenary.short_id(recent.id) %>)<p class="text-sm"><%= recent["host"]<>":"<>Integer.to_string(recent["port"]) %></p>
        </div>
      <% end %>
    </div>
    """
  end
end
