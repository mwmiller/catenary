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
      <div class="min-w-full font-sans">
        <h1>No data just yet</h1>
      </div>
    """
  end

  def render(%{card: :error} = assigns) do
    ~L"""
      <div class="min-w-full font-sans">
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
          <%= for entry <- @card["references"] do %>
            <button value="<%= entry %>" phx-click="view-entry">※</button>&nbsp;
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
      %Baobab.Entry{payload: payload} = Baobab.log_entry(a, e, log_id: l)

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
          [] ->
            []

          [{^entry, vals}] ->
            vals |> Enum.map(fn i -> Catenary.index_to_string(i) end)
        end

      :dets.close(:refs)
      extract_type(payload, a, l, forward_refs)
    rescue
      e ->
        Logger.warn(e)
        :error
    end
  end

  defp extract_type(text, a, 0, forward_refs) do
    %{
      "author" => a,
      "title" => "Test Post, Please Ignore",
      "references" => forward_refs,
      "body" => maybe_text(text),
      "published" => "in a testing period"
    }
  end

  defp extract_type(cbor, a, 8483, forward_refs) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      %{
        "author" => a,
        "title" => "Oasis: " <> data["name"],
        "body" => data["host"] <> ":" <> Integer.to_string(data["port"]),
        "references" => maybe_refs(data["references"], forward_refs),
        "published" => data["running"] |> nice_time
      }
    rescue
      _ ->
        differ = cbor |> Blake2.hash2b(5) |> BaseX.Base62.encode()

        %{
          "author" => a,
          "title" => "Legacy Oasis",
          "references" => forward_refs,
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
        "references" => maybe_refs(Map.get(data, "references"), forward_refs),
        "published" => nice_time(data["published"])
      })
    rescue
      _ ->
        %{
          "author" => a,
          "title" => "Malformed Entry",
          "body" => maybe_text(cbor),
          "references" => forward_refs,
          "published" => "unknown"
        }
    end
  end

  defp extract_type(cbor, a, 533, forward_refs) do
    try do
      {:ok, data, ""} = CBOR.decode(cbor)

      Map.merge(data, %{
        "author" => a,
        "references" => maybe_refs(data["references"], forward_refs),
        "body" => data["body"] |> Earmark.as_html!() |> Phoenix.HTML.raw(),
        "published" =>
          data
          |> Map.get("published")
          |> nice_time
      })
    rescue
      _ ->
        %{
          "author" => a,
          "title" => "Malformed Entry",
          "references" => forward_refs,
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

  defp maybe_refs(list, forward, acc \\ [])
  defp maybe_refs(nil, forward, _), do: forward
  defp maybe_refs([], forward, acc), do: Enum.reverse(acc) ++ forward

  defp maybe_refs([r | rest], forward, acc) do
    maybe_refs(rest, forward, [ref_string(r) | acc])
  end

  defp ref_string(list), do: list |> List.to_tuple() |> Catenary.index_to_string()
end
