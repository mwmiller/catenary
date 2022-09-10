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
          <p class="text-sm font-light"><%= Catenary.short_id(@card["author"]) %> &mdash; <%= @card["published"] %></p>
          <p>
          <%= for {a,_,_} = entry <- @card["back-refs"] do %>
            <button value="<%= Catenary.index_to_string(entry) %>" phx-click="view-entry"><img src="<%= Catenary.identicon(a, @iconset, 2) %>"></button>&nbsp;
          <% end %>
              ↹
          <%= for {a,_,_} = entry <- @card["fore-refs"] do %>
              <button value="<%= Catenary.index_to_string(entry) %>" phx-click="view-entry"><img src="<%= Catenary.identicon(a, @iconset, 2) %>"></button>&nbsp;
          <% end %>
        </p>
        <hr/>
        <br/>
        <div class="font-light">
        <%= @card["body"] %>
      </div>
      </div>
    """
  end

  def extract({a, l, e} = entry) do
    try do
      payload =
        case Baobab.log_entry(a, e, log_id: l) do
          {:error, :missing} -> :missing
          %Baobab.Entry{payload: pl} -> pl
          _ -> :unknown
        end

      filename =
        Path.join([
          Application.get_env(:catenary, :application_dir, "~/.catenary"),
          "references.dets"
        ])
        |> Path.expand()
        |> to_charlist

      :dets.open_file(:refs, file: filename)

      forward_refs =
        case :dets.lookup(:refs, entry) do
          [] -> []
          [{^entry, vals}] -> vals
        end

      :dets.close(:refs)
      extract_type(payload, a, l, forward_refs)
    rescue
      e ->
        Logger.warn(e)
        :error
    end
  end

  defp extract_type(:missing, a, _, forward_refs) do
    %{
      "author" => a,
      "title" => "Missing Post",
      "fore-refs" => forward_refs,
      "back-refs" => [],
      "body" => "This may become available as you sync with more peers.",
      "published" => "unknown publication"
    }
  end

  defp extract_type(:unknown, a, _, forward_refs) do
    %{
      "author" => a,
      "title" => "Loading Error",
      "fore-refs" => forward_refs,
      "back-refs" => [],
      "body" => "This should never happen to you.",
      "published" => "corrupted?"
    }
  end

  defp extract_type(text, a, 0, forward_refs) do
    %{
      "author" => a,
      "title" => "Test Post, Please Ignore",
      "fore-refs" => forward_refs,
      "back-refs" => [],
      "body" => maybe_text(text),
      "published" => "in a testing period"
    }
  end

  defp extract_type(cbor, a, 53, forward_refs) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      %{
        "author" => a,
        "title" => "Alias: ~" <> data["alias"],
        "body" =>
          Phoenix.HTML.raw(
            "For: " <>
              Catenary.short_id(data["whom"]) <>
              "<br/>Full key: " <> data["whom"]
          ),
        "fore-refs" => forward_refs,
        "back-refs" => maybe_refs(data["references"]),
        "published" => data["published"] |> nice_time
      }
    rescue
      _ ->
        differ = cbor |> Blake2.hash2b(5) |> BaseX.Base62.encode()

        %{
          "author" => a,
          "title" => "Legacy Alias",
          "fore-refs" => forward_refs,
          "back-refs" => [],
          "body" => maybe_text(cbor),
          "published" => "long ago: " <> differ
        }
    end
  end

  defp extract_type(cbor, a, 8483, forward_refs) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      %{
        "author" => a,
        "title" => "Oasis: " <> data["name"],
        "body" => data["host"] <> ":" <> Integer.to_string(data["port"]),
        "fore-refs" => forward_refs,
        "back-refs" => maybe_refs(data["references"]),
        "published" => data["running"] |> nice_time
      }
    rescue
      _ ->
        differ = cbor |> Blake2.hash2b(5) |> BaseX.Base62.encode()

        %{
          "author" => a,
          "title" => "Legacy Oasis",
          "fore-refs" => forward_refs,
          "back-refs" => [],
          "body" => maybe_text(cbor),
          "published" => "long ago: " <> differ
        }
    end
  end

  defp extract_type(cbor, a, 360_360, forward_refs) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      Map.merge(data, %{
        "author" => a,
        "body" => data["body"] |> Earmark.as_html!() |> Phoenix.HTML.raw(),
        "fore-refs" => forward_refs,
        "back-refs" => maybe_refs(data["references"]),
        "published" => nice_time(data["published"])
      })
    rescue
      _ ->
        %{
          "author" => a,
          "title" => "Malformed Entry",
          "body" => maybe_text(cbor),
          "references" => {[], forward_refs},
          "published" => "unknown"
        }
    end
  end

  defp extract_type(cbor, a, 533, forward_refs) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      Map.merge(data, %{
        "author" => a,
        "fore-refs" => forward_refs,
        "back-refs" => maybe_refs(data["references"]),
        "body" => data["body"] |> Earmark.as_html!() |> Phoenix.HTML.raw(),
        "published" => data["published"] |> nice_time
      })
    rescue
      _ ->
        %{
          "author" => a,
          "title" => "Malformed Entry",
          "fore-refs" => forward_refs,
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
end
