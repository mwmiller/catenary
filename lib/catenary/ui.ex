defmodule Catenary.UI do
  @moduledoc """
  The class strings a rail panel is built from.

  The compose panel `Catenary.Live.Navigation` drops under its triggers and
  the publish panel `Catenary.Live.PlaygroundNav` drops under its own are
  the same shape of thing — a bordered box of small labelled fields,
  224 pixels wide, in a rail — so the strings live here rather than being
  copied out of whichever panel was written first.
  """

  @doc "The bordered box a rail panel is drawn in."
  @spec panel_cls() :: binary
  def panel_cls,
    do: "rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-3"

  @doc "A field inside a rail panel: text-sized, with an amber focus ring."
  @spec input_cls() :: binary
  def input_cls,
    do:
      "w-full rounded-md border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800 px-2 py-1 text-sm text-slate-900 dark:text-slate-100 transition-colors focus:outline-none focus:border-amber-500 dark:focus:border-amber-400 focus:ring-1 focus:ring-amber-500/60 dark:focus:ring-amber-400/60"

  @doc "The small uppercase caption above a field."
  @spec label_cls() :: binary
  def label_cls,
    do:
      "block text-[11px] font-medium uppercase tracking-wide text-slate-500 dark:text-slate-400 mb-1"

  @doc "The one-line note under a panel's fields."
  @spec help_cls() :: binary
  def help_cls, do: "text-xs leading-snug text-slate-500 dark:text-slate-400"
end
