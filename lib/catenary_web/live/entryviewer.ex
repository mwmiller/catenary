defmodule Catenary.Live.EntryViewer do
  require Logger
  use Phoenix.LiveComponent
  alias Catenary.Quagga

  @impl true
  def update(%{entry: :random} = assigns, socket) do
    update(Map.merge(assigns, %{entry: Quagga.good_random_read()}), socket)
  end

  def update(%{entry: :none}, socket) do
    {:ok, assign(socket, card: :none)}
  end

  def update(%{entry: which} = assigns, socket) when is_atom(which) do
    targets = Quagga.log_ids_for_name(which)

    case assigns.store |> Enum.filter(fn {_, l, _} -> l in targets end) do
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
        <img class = "float-left m-3" src="<%= Catenary.identicon(@card["author"], 8) %>">
          <h1><%= @card["title"] %></h1>
          <p class="text-sm font-light"><%= Catenary.linked_author(@card["author"]) %> &mdash; <%= @card["published"] %></p>
          <p><%= icon_entries(@card["back-refs"]) %>&nbsp;↹&nbsp;<%= icon_entries(@card["fore-refs"]) %></p>
        <hr/>
        <br/>
        <div class="font-light">
        <%= @card["body"] %>
        </div>
        <div class="grid grid-cols-4 mt-10 space-x-4" text-xs>
          <%= for tname <- @card["tags"] do %>
            <div class="auto text-xs text-orange-600 dark:text-amber-200"><button value="<%= tname %>" phx-click="view-tag"><%= tname %></button></div>
          <% end %>
            <div class="flex flex-rows"><%= icon_entries(@card["tagged-in"]) %></div>
        </div>
      </div>
    """
  end

  # This is to create an identity "profile", but it'll also
  # give "something" when things go sideways
  def extract({a, l, e}) when l < 0 or e < 1 do
    body =
      case from_dets(a, :timelines) do
        [] ->
          "No activity"

        activity ->
          first = activity |> hd
          latest = activity |> Enum.reverse() |> hd

          "<p><button phx-click=\"view-entry\" value=\"" <>
            Catenary.index_to_string(first) <>
            "\">Earliest log entry</button></p>" <>
            "<p><button phx-click=\"view-entry\" value=\"" <>
            Catenary.index_to_string(latest) <> "\">Latest log entry</button></p>"
      end

    %{
      "author" => a,
      "title" => "Activity",
      "fore-refs" => [],
      "back-refs" => [],
      "tagged-in" => [],
      "tags" => [],
      "body" => Phoenix.HTML.raw(body),
      "published" => "latest known"
    }
  end

  def extract({a, l, e} = entry) do
    # We want failure to save here to fail loudly without any further work
    # But if it does fail later we don't mind having said it was shown
    Catenary.Preferences.update(:shown, fn ms -> MapSet.put(ms, entry) end)

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

      Map.merge(extract_type(payload, Catenary.Quagga.log_def(l)), base)
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

  defp extract_type(text, %{name: :test}) do
    %{
      "title" => "Test Post, Please Ignore",
      "back-refs" => [],
      "body" => maybe_text(text),
      "published" => "in a testing period"
    }
  end

  defp extract_type(cbor, %{name: :alias}) do
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

  defp extract_type(cbor, %{name: :oasis}) do
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

  defp extract_type(cbor, %{name: :journal}) do
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

  defp extract_type(cbor, %{name: :reply}) do
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

  defp extract_type(cbor, %{name: :tag}) do
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
      |> Enum.map(fn {_pub, v} -> v end)

    Catenary.dets_close(table)
    val
  end

  defp from_refs(entry) do
    {tags, others} =
      entry
      |> from_dets(:refs)
      |> Enum.split_with(fn {_, l, _} -> Catenary.Quagga.base_log_for_id(l) == 749 end)

    %{"tagged-in" => tags, "fore-refs" => others}
  end

  defp icon_entries(list, acc \\ "")
  defp icon_entries([], acc), do: Phoenix.HTML.raw(acc)

  defp icon_entries([entry | rest], acc) do
    icon_entries(rest, acc <> Catenary.entry_icon_link(entry, 2) <> "&nbsp;")
  end
end
