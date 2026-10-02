defmodule Catenary.Live.PlaygroundTimeline do
  @moduledoc """
  LiveComponent rendering the playground's left rail.

  On a feed screen this rail is `CatenaryWeb.Live.timeline_nav/1` — prev/next
  author and entry, where you walk a sequence to orient yourself while the
  right rail is where you act. The playground keeps that division and changes
  what gets walked: here it is a run. `Catenary.Live.AppRunner` records what
  the module asked for, what came back, what it printed and how it ended;
  this lists that in order and steps a cursor through it with the same two
  glyphs the feed rail uses, so the gesture reads the same on both screens.

  A *version* belongs here too — prev/next published version of the app,
  which is the entry-walking gesture with the app as the list — but there is
  nothing to step through until the app can be published, so it is not drawn.

  The rail is drawn from the parent's `trace` and `trace_at` assigns rather
  than from anything it owns: the run is recorded on the LiveView, which is
  also where the draft lives, so the list survives a repaint and the cursor
  is one click behind the author rather than one component instance.
  """
  use Phoenix.LiveComponent

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mt-5 min-h-[400px] w-56 shrink-0 flex flex-col gap-2">
      <div class="flex items-center justify-center gap-1">
        <button
          type="button"
          phx-click="trace-step"
          value="prev"
          title="Previous step"
          aria-label="Previous step in the trace"
          class="btn-icon"
          disabled={@trace_at <= 0}
        >⇜</button>
        <span class="text-xs text-slate-500 dark:text-slate-400">{counter(@trace, @trace_at)}</span>
        <button
          type="button"
          phx-click="trace-step"
          value="next"
          title="Next step"
          aria-label="Next step in the trace"
          class="btn-icon"
          disabled={@trace_at >= length(@trace) - 1}
        >⇝</button>
      </div>

      <p :if={@trace == []} class="px-2 text-xs text-slate-400 dark:text-slate-500">
        No trace yet. Run the buffer to record one.
      </p>

      <ol :if={@trace != []} class="flex max-h-[340px] flex-col gap-1 overflow-y-auto pr-1">
        <li
          :for={{entry, index} <- Enum.with_index(@trace)}
          class={[
            "rounded px-1.5 py-1 font-mono text-xs leading-tight",
            index == @trace_at && "bg-slate-200 dark:bg-slate-700"
          ]}
        >
          <span class="text-[10px] uppercase tracking-wide text-slate-400 dark:text-slate-500">
            {entry["kind"]}
          </span>
          <span class="block break-words text-slate-700 dark:text-slate-200">{entry["detail"]}</span>
        </li>
      </ol>
    </div>
    """
  end

  defp counter([], _at), do: "—"
  defp counter(trace, at), do: "#{at + 1}/#{length(trace)}"
end
