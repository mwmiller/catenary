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

  # These should likely be macros as well, but I wrote them by hand first.
  defp istatus([{:references, :not_running} | rest], chars), do: istatus(rest, ["※" | chars])
  defp istatus([{:references, _pid} | rest], chars), do: istatus(rest, ["𝍂" | chars])
  defp istatus([{:aliases, :not_running} | rest], chars), do: istatus(rest, ["⍱" | chars])
  defp istatus([{:aliases, _pid} | rest], chars), do: istatus(rest, ["⍲" | chars])
  defp istatus([{:tags, :not_running} | rest], chars), do: istatus(rest, ["‽" | chars])
  defp istatus([{:tags, _pid} | rest], chars), do: istatus(rest, ["⸘" | chars])
  defp istatus([{:timelines, :not_running} | rest], chars), do: istatus(rest, ["∥" | chars])
  defp istatus([{:timelines, _pid} | rest], chars), do: istatus(rest, ["∦" | chars])
end
