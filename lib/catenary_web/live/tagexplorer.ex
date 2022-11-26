defmodule Catenary.Live.TagExplorer do
  require Logger
  use Phoenix.LiveComponent

  @impl true
  def update(%{entry: which} = assigns, socket) do
    {:ok, assign(socket, Map.merge(assigns, %{card: extract(which)}))}
  end

  @impl true
  def render(%{card: :none} = assigns), do: Catenary.GeneriCard.no_data_card(assigns)

  def render(%{card: :error} = assigns), do: Catenary.GeneriCard.error_card(assigns)

  def render(assigns) do
    ~L"""
     <div id="tagexplore-wrap" class="col-span-2 overflow-y-auto max-h-screen m-2 p-x-2">
      <h1 class="text=center">Tag Explorer</h1>
        <%= for g <-  @card["tags"] do %>
      <div class="grid grid-cols-3 mt-10">
        <%= g %>
      </div>
      <% end %>
    </div>
    """
  end

  defp extract(:all) do
    Catenary.dets_open(:tags)

    tags =
      :dets.match(:tags, :"$1")
      |> Enum.reduce([], fn [{f, i} | _], a ->
        case f do
          {"", t} ->
            [
              {t, Enum.any?(i, fn {_t, e} -> not Catenary.Preferences.shown?(e) end), length(i)}
              | a
            ]

          _ ->
            a
        end
      end)
      |> size_group
      |> link_groups([])

    Catenary.dets_close(:tags)
    %{"tags" => tags}
  end

  defp extract(_), do: :none

  defp size_group(items) do
    items
    |> Enum.group_by(fn {_, _, c} -> trunc(:math.log(c)) end)
    |> Map.to_list()
    |> Enum.sort(:desc)
    |> Enum.reduce([], fn {_s, i}, acc -> [Enum.shuffle(i) | acc] end)
    |> Enum.reverse()
  end

  defp link_groups([], acc), do: Enum.reverse(acc)
  defp link_groups([tags | rest], acc), do: link_groups(rest, [to_links(tags) | acc])

  defp to_links(tags) do
    tags
    |> Enum.map(fn {t, n, _c} ->
      "<div><button value=\"" <>
        t <>
        "\" phx-click=\"view-tag\"><p class=\"tighter text-amber-900 dark:text-amber-100 " <>
        new_or_not(n) <> "\">" <> t <> "</p></button></div>"
    end)
    |> Phoenix.HTML.raw()
  end

  defp new_or_not(true), do: "underline decoration-dotted"
  defp new_or_not(false), do: ""
end
