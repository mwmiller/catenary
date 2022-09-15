defmodule Catenary.Live.Navigation do
  use Phoenix.LiveComponent
  alias Catenary.Quagga

  @impl true
  def update(assigns, socket) do
    {whom, ali} = alias_info(assigns.entry)
    posts_avail = posts_avail(assigns.entry)
    na = Map.merge(assigns, %{whom: whom, ali: ali, posts_avail: posts_avail})

    {:ok,
     assign(socket, identity: assigns.identity, iconset: assigns.iconset, lower_nav: extra_nav(na))}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div class="align-top min-w-full font-sans">
      <div class="text-xl">
        <button value="origin" phx-click="nav"><img src="<%= Catenary.identicon(@identity, @iconset, 2) %>"></button>
        <button value="prev-author" phx-click="nav">⇧</button>
        <button value="prev-entry" phx-click="nav">☚</button>
        <button value="next-entry" phx-click="nav">☛</button>
        <button value="next-author" phx-click="nav">⇩</button>
        <button phx-click="toggle-posting">✎</button>
        <button phx-click="toggle-aliases">∼</button>
        <button phx-click="toggle-tags">#</button>
      </div>
      <br/>
      <%= @lower_nav %>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :posting} = assigns) do
    ~L"""
    <div id="posting" class="font-sans">
      <form method="post" id="posting-form" phx-submit="new-entry">
        <select name=log_id  class="bg-white dark:bg-black">
          <%= for a <- @posts_avail do %>
          <option value="<%= Quagga.log_id_for_name(a) %>"><%= String.capitalize(Atom.to_string(a)) %></option>
          <% end %>
        </select>
        <%= if is_tuple(@entry) do %>
          <input type="hidden" name="ref" value="<%= Catenary.index_to_string(@entry) %>">
        <% end %>
        <br/>
        <input class="bg-white dark:bg-black" type="text" name="title"/>
        <br/>
        <textarea class="bg-white dark:bg-black" name="body" rows="8" cols="35"></textarea>
        <hr/>
        <button phx-disable-with="𝄇" type="submit">➲</button>
      </form>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :aliases} = assigns) do
    ~L"""
    <div id="aliases">
      <%= if is_tuple(@entry) do %>
       <form method="post" id="alias-form" phx-submit="new-alias">
         <input type="hidden" name="ref" value="<%= Catenary.index_to_string(@entry) %>">
         <p>
           <input type="hidden" name="whom" value="<%= @whom %>" />
         <div class="flex flex-row space-x-4">
          <label for="wref">↹</label>
          <div class="flex-auto"><input type="radio" id="wref" name="doref" value="include" checked/></div>
          <label for="noref">⊗</label>
          <div class="flex-auto"><input type="radio" id="noref" name="doref" value="exclude" /></div>
         </div>
         <div class="flex flex-row p-2">
          <div class="flex-auto"><%= Catenary.short_id(@whom) %></div>
          <div class="flex-auto"><img src="<%= Catenary.identicon(@whom, @iconset, 4) %>"></div>
         </div>
         <label for="alias">～</label>
         <input class="bg-white dark:bg-black" name="alias" value="<%= @ali %>" type="text" size="16" />
         <hr/>
         <button phx-disable-with="𝄇" type="submit">➲</button>
       </form>
      <% else %>
          ‽
      <% end %>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :tags} = assigns) do
    ~L"""
    <div id="tags">
      <%= if is_tuple(@entry) do %>
       <form method="post" id="tag-form" phx-submit="new-tag">
         <input type="hidden" name="ref" value="<%= Catenary.index_to_string(@entry) %>">
         <p>
           <%= for n <- 0..3 do %>
             <label for="tag<%= n %>">#</label>
        <input class="bg-white dark:bg-black" name="tag<%= n %>" type="text" size="16" /><br/>
        <% end %>
         <hr/>
         <button phx-disable-with="𝄇" type="submit">➲</button>
       </form>
      <% else %>
          ‽
      <% end %>
    </div>
    """
  end

  defp extra_nav(_), do: ""

  # We're looking at someone else's alias info, let's offer to use it
  defp alias_info({a, 53, e}) do
    try do
      %Baobab.Entry{payload: payload} = Baobab.log_entry(a, e, log_id: 53)
      {:ok, data, ""} = CBOR.decode(payload)
      {data["whom"], data["alias"]}
    rescue
      _ -> {a, ""}
    end
  end

  defp alias_info({a, _, _}), do: {a, ""}
  defp alias_info(_), do: {"", ""}

  defp posts_avail(atom) when is_atom(atom), do: [:journal]
  # This will have more logic later
  defp posts_avail(_), do: [:reply | posts_avail(:none)]
end
