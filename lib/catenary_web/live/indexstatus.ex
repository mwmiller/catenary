defmodule Catenary.Live.IndexStatus do
  @moduledoc """
  LiveComponent rendering the current indexing status.
  """
  use Phoenix.LiveComponent
  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @log_type_map %{
    about: [:about],
    aliases: [:alias],
    challenges: [:challenge],
    graph: [:graph],
    images: [:gif, :png, :jpeg],
    mentions: [:mention],
    oases: [:oasis],
    reactions: [:react],
    references: [:reply],
    tags: [:tag],
    timelines: [:journal]
  }

  @impl true
  def render(assigns) do
    ~H"""
    <div class="index-strip">
      <%= for {which, {char, state}} <- visible_indices(@indexing) do %>
        <div class={pill_class(state)} title={pill_title(which, state)}>
          <span aria-hidden="true">{char}</span>
          <span class="sr-only">{pill_title(which, state)}</span>
        </div>
      <% end %>
    </div>
    """
  end

  defp visible_indices(indexing) do
    Enum.filter(indexing, fn {which, _} ->
      logs = Map.get(@log_type_map, which, [])
      logs == [] or Enum.any?(logs, &Catenary.Preferences.accept_log_name?/1)
    end)
  end

  defp pill_class(:running),
    do:
      "flex-auto p-1 font-bold text-amber-900 dark:text-amber-200 bg-amber-100 dark:bg-amber-900/60 rounded cursor-default"

  defp pill_class(:idle),
    do: "flex-auto p-1 text-slate-600 dark:text-slate-400 cursor-default"

  defp pill_title(which, :running), do: "Indexing " <> pretty(which) <> "..."
  defp pill_title(which, :idle), do: pretty(which) <> " indexed"

  defp pretty(which), do: which |> Atom.to_string() |> String.capitalize()
end
