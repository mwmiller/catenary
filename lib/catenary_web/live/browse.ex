defmodule Catenary.Live.Browse do
  use Phoenix.LiveComponent
  @impl true
  def render(assigns) do
    ~L"""
      <div>
        <%= if [] == @store do %>
         <h1>Waiting for logs</h1>
        <% else %>
         <table class="min-w-full">
           <tr >
             <th><button value="asc-author" phx-click="sort">↓</button> Author <button value="desc-author" phx-click="sort">↑</button></th>
             <th><button value="asc-logid" phx-click="sort">↓</button> Log Id <button value="desc-logid" phx-click="sort">↑</button></th>
             <th><button value="asc-seq" phx-click="sort">↓</button> Max Seq <button value="desc-seq" phx-click="sort">↑</button></th>
           </tr>
           <%= for {author, log_id, seq} <- @store do %>
             <tr class="text-center"><td><%= Catenary.short_id(author)  %>
                <img class="m-0.5 float-right align-middle" src="data:image/png;base64,<%= Excon.ident(author, base64: true, magnification: 2)%>">
             </td><td><%= log_id %></td><td><%= seq %></td></tr>
           <% end %>
         </table>
        <% end %>
      </div>
    """
  end
end
