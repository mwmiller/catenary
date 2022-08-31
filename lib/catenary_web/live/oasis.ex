defmodule Catenary.Live.OasisBox do
  use Phoenix.LiveComponent
  @impl true
  def render(assigns) do
    ~L"""
    <div>
      <%= for {recent, index}  <- Enum.with_index(@watering) do %>
        <div title="as of <%= ago_string(recent.age, 2)%>" class="<%= case rem(index, 2)  do
        0 ->  "bg-emerald-200 dark:bg-cyan-700"
        1 -> "bg-emerald-400 dark:bg-sky-700"
      end %>"> <img class="m-1 float-right align-middle" src="<%= Catenary.identicon(recent.id, @iconset)%>">
              <%= recent["name"] %> (<%= Catenary.short_id(recent.id) %>)<br><%= recent["host"]<>":"<>Integer.to_string(recent["port"]) %>
        </div>
      <% end %>
    </div>
    """
  end

  defp ago_string(sago, n) do
    "about " <> compile_sections(sago, n, []) <> " ago"
  end

  defp compile_sections(sago, _, acc) when sago <= 0, do: acc |> Enum.reverse() |> Enum.join("")
  defp compile_sections(_sago, n, acc) when length(acc) == n, do: compile_sections(0, n, acc)

  defp compile_sections(sago, n, acc) when div(sago, 86400) > 0 do
    u = div(sago, 86400)
    compile_sections(sago - 86400 * u, n, [Integer.to_string(u) <> "d" | acc])
  end

  defp compile_sections(sago, n, acc) when div(sago, 3600) > 0 do
    u = div(sago, 3600)
    compile_sections(sago - 3600 * u, n, [Integer.to_string(u) <> "h" | acc])
  end

  defp compile_sections(sago, n, acc) when div(sago, 60) > 0 do
    u = div(sago, 60)
    compile_sections(sago - 60 * u, n, [Integer.to_string(u) <> "m" | acc])
  end

  defp compile_sections(sago, n, acc) do
    compile_sections(0, n, [Integer.to_string(sago) <> "s" | acc])
  end
end
