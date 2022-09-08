defmodule Catenary.Live.Navigation do
  use Phoenix.LiveComponent
  alias Catenary.Quagga

  @impl true
  def update(assigns, socket) do
    # As things expand, we'll use this info to build a proper
    # interface to navigate.
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~L"""
      <div class="align-top min-w-full font-sans">
        <div class="text-xl">
         <button value="origin" phx-click="nav">⌱</button>
         <button value="prev-author" phx-click="nav">⇧</button>
         <button value="prev-entry" phx-click="nav">☚</button>
         <button value="next-entry" phx-click="nav">☛</button>
         <button value="next-author" phx-click="nav">⇩</button>
         <button phx-click="toggle-posting">✎</button>
         <button phx-click="toggle-aliases">∼</button>
       </div>
         <br/>
     <%= if @extra_nav == :aliases do %>
           <div id="aliases">
       <%= if is_tuple(@entry) do %>
        <form method="post" id="alias-form" phx-submit="new-alias">
        <select name="identity" id="select_identity" phx-change="identity-change" class="bg-white dark:bg-black">
         <%= for {i, b62} <- @identities do %>
           <option value="<%= i %>"  <%= if @identity == i,  do: "selected" %>>
      <%= i<> " (" <> Catenary.short_id(b62)<>")" %>
           </option>
         <% end %>
         <input type="hidden" name="ref" value="<%= Catenary.index_to_string(@entry) %>">
       <p>
           <input type="radio" name="doref" value="include" checked/>&nbsp;↹
         <br/>
           <input type="radio" name="doref" value="include" />&nbsp;⊗
         <br/>
       <input type="hidden" name="whom" value="<%= elem(@entry,0) %>" />
       <label for="alias"><img src="<%= Catenary.identicon(elem(@entry,0), @iconset, 4) %>"> <%= Catenary.short_id(elem(@entry, 0)) %><br/>～</label>
           <input class="bg-white dark:bg-black" name="alias" type="text" size="16">
       <hr/>
       <button phx-disable-with="𝄇" type="submit">➲</button>
           </form>
           <% else %>
             ‽
           <% end %>
         </div>
         <% end %>
         <%= if @extra_nav == :posting do %>
         <div id="posting" class="font-sans">
        <form method="post" id="posting-form" phx-submit="new-entry">
    <select name="identity" id="select_identity" phx-change="identity-change" class="bg-white dark:bg-black">
         <%= for {i, b62} <- @identities do %>
           <option value="<%= i %>"  <%= if @identity == i,  do: "selected" %>>
      <%= i<> " (" <> Catenary.short_id(b62)<>")" %>
           </option>
         <% end %>
       </select>
       <select name=log_id  class="bg-white dark:bg-black">
         <%= for a <- posts_avail(@entry) do %>
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
    <% end %>
    </div>
    """
  end

  defp posts_avail(atom) when is_atom(atom), do: [:journal]
  # This will have more logic later
  defp posts_avail(_), do: [:reply | posts_avail(:none)]
end
