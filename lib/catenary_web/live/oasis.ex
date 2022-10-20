defmodule Catenary.Live.OasisBox do
  use Phoenix.LiveComponent
  @impl true
  def update(assigns, socket) do
    {:ok,
     assign(socket,
       indexing: index_status(assigns.indexing),
       nodes: assigns.oases,
       connected: Enum.map(assigns.connections, &id_mapper/1)
     )}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div class="font-mono text-xs">
      <%= for {recent, index}  <- Enum.with_index(@nodes) do %>
        <div class="my-1 p-1 <%= case rem(index, 2)  do
        0 ->  "bg-zinc-200 dark:bg-stone-700"
        1 -> "bg-slate-200 dark:bg-slate-700"
      end %>"><img class="m-1 float-right align-middle" src="<%= Catenary.identicon(elem(recent.id, 0), 2)%>">
        <p><%= recent["name"] %> (<%= Catenary.linked_author(elem(recent.id, 0)) %>)
        <%= if recent.id in @connected do %>
          ⥀
        <% else %>
        <button phx-click="connect" phx-disable-with="↯" value="<%= Catenary.index_to_string(recent.id) %>">⇆</button>
        <% end %>
        </p>

        </div>
      <% end %>
        <%= @indexing %>
    </div>
    """
  end

  defp index_status(index_map), do: istatus(Map.to_list(index_map) |> Enum.sort(:desc), [])

  defp istatus([], chars) do
    stat = Enum.join(chars, "&nbsp;")
    Phoenix.HTML.raw("<p class=\"text-center\">" <> stat <> "</p>")
  end

  # These should likely be macros as well, but I wrote them by hand first.
  defp istatus([{:references, :not_running} | rest], chars), do: istatus(rest, ["※" | chars])
  defp istatus([{:references, _pid} | rest], chars), do: istatus(rest, ["𝍂" | chars])
  defp istatus([{:aliases, :not_running} | rest], chars), do: istatus(rest, ["⍱" | chars])
  defp istatus([{:aliases, _pid} | rest], chars), do: istatus(rest, ["⍲" | chars])
  defp istatus([{:tags, :not_running} | rest], chars), do: istatus(rest, ["‽" | chars])
  defp istatus([{:tags, _pid} | rest], chars), do: istatus(rest, ["⸘" | chars])
  defp istatus([{:timelines, :not_running} | rest], chars), do: istatus(rest, ["∥" | chars])
  defp istatus([{:timelines, _pid} | rest], chars), do: istatus(rest, ["∦" | chars])

  defp id_mapper({_, %{id: id}}), do: id
  defp id_mapper(_), do: ""
end
