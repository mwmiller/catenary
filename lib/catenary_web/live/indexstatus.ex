defmodule Catenary.Live.IndexStatus do
  @moduledoc """
  LiveComponent rendering the current indexing status.
  """
  use Phoenix.LiveComponent
  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="status flex items-center gap-1 font-mono text-xs text-center mx-1 w-max">
      <%= for {which, {char, state}} <- @indexing do %>
        <div class={pill_class(state)} title={pill_title(which, state)}>{char}</div>
      <% end %>
      <button
        type="button"
        phx-click="reindex"
        phx-disable-with="⟳"
        title="Reindex"
        class="shrink-0 text-xs px-1.5 py-0.5 rounded hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors"
      >⏵</button>
    </div>
    """
  end

  defp pill_class(:running),
    do:
      "flex-auto p-1 font-bold text-amber-700 dark:text-amber-300 bg-amber-200 dark:bg-amber-900/60 rounded cursor-default"

  defp pill_class(:idle),
    do: "flex-auto p-1 text-slate-500 dark:text-slate-400 cursor-default"

  defp pill_title(which, :running), do: "Indexing " <> pretty(which) <> "..."
  defp pill_title(which, :idle), do: pretty(which) <> " indexed"

  defp pretty(which), do: which |> Atom.to_string() |> String.capitalize()
end
