defmodule Catenary.Live.ImageExplorer do
  @moduledoc """
  LiveComponent rendering an explorer of image entries.
  """
  use Phoenix.LiveComponent
  alias Catenary.Display

  @impl true
  def update(%{entry: which, aliases: aliases} = assigns, socket) do
    {:ok,
     assign(socket, Map.merge(assigns, %{
       entry: which,
       card: extract(aliases)
     }))}
  end

  @impl true
  def render(%{card: :none} = assigns), do: Catenary.GeneriCard.no_data_card(assigns)

  def render(%{card: :error} = assigns), do: Catenary.GeneriCard.error_card(assigns)

  def render(assigns) do
    ~H"""
    <div id="image-explore-wrap" class="col-span-2 overflow-y-auto max-h-screen m-2 px-2">
      <div class="flex flex-col gap-5">
        <div class="flex items-center justify-between gap-3">
          <h1 class="text-lg font-semibold text-slate-800 dark:text-slate-100">Image Explorer</h1>
          <div class="flex gap-1 rounded-lg bg-slate-100 dark:bg-slate-800 p-1">
            <%= for a <- @card |> Map.keys |> Enum.sort do %>
              <button
                value={a}
                phx-click="arrange"
                phx-target={@myself}
                class={"px-2 py-1 text-xs rounded-md transition-colors #{if @entry == a, do: "bg-white dark:bg-slate-700 text-amber-700 dark:text-amber-300 shadow-sm", else: "text-slate-500 dark:text-slate-400 hover:text-slate-700 dark:hover:text-slate-200"}"}
              >
                {a}
              </button>
            <% end %>
          </div>
        </div>
        <%= for {t, g} <- (@card[@entry] || []) |> Enum.sort do %>
          <div class="flex flex-col gap-2">
            <h4 class="text-xs uppercase tracking-wide text-slate-400 dark:text-slate-500">{t}</h4>
            <div class="flex flex-row flex-wrap gap-2">
              <%= for i <- g do %>
                {i}
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("arrange", %{"value" => how}, socket) do
    {:noreply, assign(socket, entry: String.to_existing_atom(how))}
  end

  defp extract(aliases) do
    case :ets.lookup(:images, :map) do
      [{:map, full_map}] -> full(Map.to_list(full_map), aliases)
      _ -> :none
    end
  end

  defp full(map, aliases, acc \\ [])
  defp full([], _, acc), do: acc |> Enum.into(%{})

  defp full([{key, subitems} | rest], aliases, acc),
    do: full(rest, aliases, [{key, grouped(Map.to_list(subitems), aliases)} | acc])

  defp grouped(images, aliases, acc \\ [])
  defp grouped([], _, acc), do: acc

  defp grouped([{title, items} | rest], aliases, acc) do
    # This is probably a bad assumption long term
    # but all of this is very hasky anyway
    t =
      case is_binary(title) and byte_size(title) == 43 do
        true -> Display.short_id(title, aliases)
        false -> title
      end

    grouped(rest, aliases, [{t, displayable(items)} | acc])
  end

  defp displayable(entries, acc \\ [])
  defp displayable([], images), do: images

  defp displayable([{src, entry} | rest], images) do
    img_tag =
      "<img class=\"w-32 h-32 object-cover rounded-lg border border-slate-200 dark:border-slate-700 shadow-sm hover:scale-105 hover:shadow-md hover:border-amber-500 dark:hover:border-amber-400 transition-all\" src=" <>
        src <> ">"

    val =
      ("<div class=\"flex-auto\">" <>
         Display.avatar_view_entry_button(entry, img_tag) <> "</div>")
      |> Phoenix.HTML.raw()

    displayable(rest, [val | images])
  end
end
