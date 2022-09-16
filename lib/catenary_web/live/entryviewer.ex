defmodule Catenary.Live.EntryViewer do
  require Logger
  use Phoenix.LiveComponent
  alias Catenary.Quagga

  @impl true
  def update(%{entry: :random} = assigns, socket) do
    update(Map.merge(assigns, %{entry: Quagga.log_type()}), socket)
  end

  def update(%{entry: :none}, socket) do
    {:ok, assign(socket, card: :none)}
  end

  def update(%{entry: which} = assigns, socket) when is_atom(which) do
    # Eventually there will be other selection criteria
    # For now, all is latest from random author
    target_log_id = Quagga.log_id_for_name(which)

    case assigns.store |> Enum.filter(fn {_, l, _} -> l == target_log_id end) do
      [] ->
        {:ok, assign(socket, card: :none)}

      entries ->
        entry = Enum.random(entries)

        case extract(entry) do
          :error ->
            update(assigns, socket)

          card ->
            Phoenix.PubSub.local_broadcast(Catenary.PubSub, "ui", %{entry: entry})
            {:ok, assign(socket, Map.merge(assigns, %{card: card}))}
        end
    end
  end

  def update(%{entry: which} = assigns, socket) do
    {:ok, assign(socket, Map.merge(assigns, %{card: extract(which)}))}
  end

  @impl true
  def render(%{card: :none} = assigns) do
    ~L"""
      <div class="min-w-full font-sans row-span-full">
        <h1>No data just yet</h1>
      </div>
    """
  end

  def render(%{card: :error} = assigns) do
    ~L"""
      <div class="min-w-full font-sans row-span-full">
        <h1>Unrenderable card</h1>
      </div>
    """
  end

  def render(assigns) do
    ~L"""
      <div class="min-w-full font-sans row-span-full">
        <img class = "float-left m-3" src="<%= Catenary.identicon(@card["author"], @iconset, 8) %>">
          <h1><%= @card["title"] %></h1>
          <p class="text-sm font-light"><%= Catenary.linked_author(@card["author"]) %> &mdash; <%= @card["published"] %></p>
          <p><%= icon_entries(@card["back-refs"], @iconset) %>&nbsp;↹&nbsp;<%= icon_entries(@card["fore-refs"], @iconset) %></p>
        <hr/>
        <br/>
        <div class="font-light">
        <%= @card["body"] %>
        </div>
        <div class="grid grid-cols-4 mt-10 space-x-4" text-xs>
          <%= for tname <- @card["tags"] do %>
            <div class="auto text-xs text-orange-600 dark:text-amber-200"><button value="<%= tname %>" phx-click="view-tag"><%= tname %></button></div>
          <% end %>
            <div class="flex flex-rows"><%= icon_entries(@card["tagged-in"], @iconset) %></div>
        </div>
      </div>
    """
  end

  # This is to create an identity "profile", but it'll also
  # give "something" when thing's go sideways
  def extract({a, l, e}) when l < 0 or e < 1 do
    # We don't want to have the store in the assigns
    # just for this.  Extra rendering overhead
    body =
      Baobab.stored_info()
      |> Enum.filter(fn {author, _, _} -> author == a end)
      |> Enum.reduce("<ul>", fn entry, a ->
        a <>
          case Catenary.Quagga.log_def(elem(entry, 1)) do
            %{name: na} ->
              "<li><button value=\"" <>
                Catenary.index_to_string(entry) <>
                "\" phx-click=\"view-entry\">" <>
                String.capitalize(Atom.to_string(na)) <> "</button></li>"

            _ ->
              ""
          end
      end)

    %{
      "author" => a,
      "title" => "Activity",
      "fore-refs" => [],
      "back-refs" => [],
      "tagged-in" => [],
      "tags" => [],
      "body" => Phoenix.HTML.raw(body <> "</ul>"),
      "published" => "latest known"
    }
  end

  def extract({a, l, e} = entry) do
    try do
      payload =
        case Baobab.log_entry(a, e, log_id: l) do
          {:error, :missing} -> :missing
          %Baobab.Entry{payload: pl} -> pl
          _ -> :unknown
        end

      base =
        Map.merge(
          %{
            "author" => a,
            "tags" => from_dets(entry, :tags)
          },
          from_refs(entry)
        )

      Map.merge(extract_type(payload, l), base)
    rescue
      e ->
        Logger.warn(e)
        :error
    end
  end

  defp extract_type(:missing, _) do
    %{
      "title" => "Missing Post",
      "back-refs" => [],
      "body" => "This may become available as you sync with more peers.",
      "published" => "unknown publication"
    }
  end

  defp extract_type(:unknown, _) do
    %{
      "title" => "Loading Error",
      "back-refs" => [],
      "body" => "This should never happen to you.",
      "published" => "corrupted?"
    }
  end

  defp extract_type(text, 0) do
    %{
      "title" => "Test Post, Please Ignore",
      "back-refs" => [],
      "body" => maybe_text(text),
      "published" => "in a testing period"
    }
  end

  defp extract_type(cbor, 53) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      %{
        "title" => "Alias: ~" <> data["alias"],
        "body" =>
          Phoenix.HTML.raw(
            "For: " <>
              Catenary.short_id(data["whom"]) <>
              "<br/>Full key: " <> data["whom"]
          ),
        "back-refs" => maybe_refs(data["references"]),
        "published" => data["published"] |> nice_time
      }
    rescue
      _ ->
        differ = cbor |> Blake2.hash2b(5) |> BaseX.Base62.encode()

        %{
          "title" => "Legacy Alias",
          "back-refs" => [],
          "body" => maybe_text(cbor),
          "published" => "long ago: " <> differ
        }
    end
  end

  defp extract_type(cbor, 8483) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      %{
        "title" => "Oasis: " <> data["name"],
        "body" => data["host"] <> ":" <> Integer.to_string(data["port"]),
        "back-refs" => maybe_refs(data["references"]),
        "published" => data["running"] |> nice_time
      }
    rescue
      _ ->
        differ = cbor |> Blake2.hash2b(5) |> BaseX.Base62.encode()

        %{
          "title" => "Legacy Oasis",
          "back-refs" => [],
          "body" => maybe_text(cbor),
          "published" => "long ago: " <> differ
        }
    end
  end

  defp extract_type(cbor, 360_360) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      Map.merge(data, %{
        "body" => data["body"] |> Earmark.as_html!() |> Phoenix.HTML.raw(),
        "back-refs" => maybe_refs(data["references"]),
        "published" => nice_time(data["published"])
      })
    rescue
      _ ->
        %{
          "title" => "Malformed Entry",
          "body" => maybe_text(cbor),
          "back-refs" => [],
          "published" => "unknown"
        }
    end
  end

  defp extract_type(cbor, 533) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      Map.merge(data, %{
        "back-refs" => maybe_refs(data["references"]),
        "body" => data["body"] |> Earmark.as_html!() |> Phoenix.HTML.raw(),
        "published" => data["published"] |> nice_time
      })
    rescue
      _ ->
        %{
          "title" => "Malformed Entry",
          "back-refs" => [],
          "body" => maybe_text(cbor),
          "published" => "unknown"
        }
    end
  end

  defp extract_type(cbor, 749) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      tagdivs =
        data["tags"]
        |> Enum.map(fn t ->
          "<div class=\"text-orange-600 dark:text-amber-200\"><button value=\"" <>
            t <> "\" phx-click=\"view-tag\">" <> t <> "</button></div>"
        end)

      body = "<div>" <> Enum.join(tagdivs, "") <> "</div>"

      Map.merge(data, %{
        "title" => "Tagging",
        "back-refs" => maybe_refs(data["references"]),
        "body" => Phoenix.HTML.raw(body),
        "published" => data["published"] |> nice_time
      })
    rescue
      _ ->
        %{
          "title" => "Malformed Entry",
          "back-refs" => [],
          "body" => maybe_text(cbor),
          "published" => "unknown"
        }
    end
  end

  defp nice_time(t) do
    t
    |> Timex.parse!("{ISO:Extended}")
    |> Timex.Timezone.convert(Timex.Timezone.local())
    |> Timex.Format.DateTime.Formatter.format!("{YYYY}-{0M}-{0D} {kitchen}")
  end

  defp maybe_text(t) when is_binary(t) do
    case String.printable?(t) do
      true -> t
      false -> "unprintable binary"
    end
  end

  defp maybe_text(_), do: "Not binary"

  defp maybe_refs(list, acc \\ [])
  defp maybe_refs(nil, _), do: []

  defp maybe_refs([], acc), do: Enum.reverse(acc)

  defp maybe_refs([r | rest], acc) do
    maybe_refs(rest, [List.to_tuple(r) | acc])
  end

  defp from_dets(entry, table) do
    Catenary.dets_open(table)

    val =
      case :dets.lookup(table, entry) do
        [] -> []
        [{^entry, v}] -> v
      end

    Catenary.dets_close(table)
    val
  end

  defp from_refs(entry) do
    {tags, others} = entry |> from_dets(:refs) |> Enum.split_with(fn {_, l, _} -> l == 749 end)

    %{"tagged-in" => tags, "fore-refs" => others}
  end

  defp icon_entries(list, icons, acc \\ "")
  defp icon_entries([], _icons, acc), do: Phoenix.HTML.raw(acc)

  defp icon_entries([{a, _, _} = entry | rest], icons, acc) do
    icon_entries(
      rest,
      icons,
      acc <>
        "<button value=\"" <>
        Catenary.index_to_string(entry) <>
        "\" phx-click=\"view-entry\"><img src=\"" <>
        Catenary.identicon(a, icons, 2) <> "\"></button>&nbsp;"
    )
  end
end
