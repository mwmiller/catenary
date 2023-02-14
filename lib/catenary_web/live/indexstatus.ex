defmodule Catenary.Live.IndexStatus do
  use Phoenix.LiveComponent
  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, indexing: index_status(assigns.indexing))}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div class="font-mono text-xs text-center my-2">
        <%= @indexing %>
    </div>
    """
  end

  defp index_status(index_map), do: istatus(Map.to_list(index_map) |> Enum.sort(:desc), [])

  defp istatus([], chars), do: Enum.join(chars, " ")

  @status_indica [
    {:references, "🜪", "🜚"},
    {:aliases, "⍲", "⍱"},
    {:tags, "⸘", "‽"},
    {:timelines, "⫝̸", "⫝"},
    {:graph, "∌", "∋"},
    {:reactions, "☽", "☾"},
    {:mentions, "⎒", "⎑"},
    {:about, "⧞", "∞"},
    {:images, "≒", "≓"}
  ]

  for {index, running, idle} <- @status_indica do
    defp istatus([{unquote(index), pid} | rest], chars) when is_pid(pid),
      do: istatus(rest, [unquote(running) | chars])

    defp istatus([{unquote(index), _shash} | rest], chars),
      do: istatus(rest, [unquote(idle) | chars])
  end
end
