defmodule Catenary.Live.Journal do
  use Phoenix.LiveComponent

  @impl true
  def update(%{journal: which} = assigns, socket) when is_atom(which) do
    # Eventually there will be other selection criteria
    # For now, all is latest from random author
    journal = assigns.store |> Enum.filter(fn {_, l, _} -> l == 360_360 end) |> Enum.random()

    {:ok, assign(socket, Map.merge(assigns, %{journal: journal, card: extract(journal)}))}
  end

  def update(%{journal: which} = assigns, socket) do
    {:ok, assign(socket, Map.merge(assigns, %{card: extract(which)}))}
  end

  @impl true
  def render(assigns) do
    ~L"""
      <div class="min-w-full">
        <img class = "float-left m-3" src="<%= Catenary.identicon(@card["author"], @iconset, 8) %>">
        <h1><%= @card["title"] %></h1>
        <h2><%= Catenary.short_id(@card["author"]) %></h2>
        <h3><%= @card["published"] %></h3>
        <hr/>
        <br/>
        <pre><%= @card["body"] %></pre>
      </div>
    """
  end

  defp extract({a, l, e}) do
    %Baobab.Entry{payload: cbor} = Baobab.log_entry(a, e, log_id: l)
    {:ok, data, ""} = CBOR.decode(cbor)
    Map.merge(data, %{"author" => a})
  end
end
