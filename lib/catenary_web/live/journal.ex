defmodule Catenary.Live.Journal do
  use Phoenix.LiveComponent

  @impl true
  def update(%{journal: which} = assigns, socket) when is_atom(which) do
    # Eventually there will be other selection criteria
    # For now, all is latest from random author
    journal = assigns.store |> Enum.filter(fn {_, l, _} -> l == 360_360 end) |> Enum.random()

    Phoenix.PubSub.local_broadcast(Catenary.PubSub, "ui", %{entry: journal})
    {:ok, assign(socket, Map.merge(assigns, %{journal: journal, card: extract(journal)}))}
  end

  def update(%{journal: which} = assigns, socket) do
    {:ok, assign(socket, Map.merge(assigns, %{card: extract(which)}))}
  end

  @impl true
  def render(assigns) do
    ~L"""
      <div class="min-w-full font-sans">
        <img class = "float-left m-3" src="<%= Catenary.identicon(@card["author"], @iconset, 8) %>">
          <h1><%= @card["title"] %></h1>
          <p class="text-sm font-light"><%= Catenary.short_id(@card["author"]) %> &mdash; <%= @card["published"] %></p>
        <hr/>
        <br/>
        <div class="font-light">
        <%= @card["body"] %>
      </div>
      </div>
    """
  end

  defp extract({a, l, e}) do
    %Baobab.Entry{payload: cbor} = Baobab.log_entry(a, e, log_id: l)
    {:ok, data, ""} = CBOR.decode(cbor)

    Map.merge(data, %{
      "author" => a,
      "body" => data |> Map.get("body") |> Earmark.as_html!() |> Phoenix.HTML.raw(),
      "published" =>
        data
        |> Map.get("published")
        |> Timex.parse!("{ISO:Extended}")
        |> Timex.Timezone.convert(Timex.Timezone.local())
        |> Timex.Format.DateTime.Formatter.format!("{YYYY}-{0M}-{0D} {kitchen}")
    })
  end
end
