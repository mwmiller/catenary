defmodule Catenary.Live.EntryCreator do
  use Phoenix.LiveComponent
  alias Catenary.Quagga

  @impl true
  # As always, we start with a simple interface
  # and iterate to make it incomprehensible and annoying
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~L"""
      <div class="min-w-full font-sans">
        <form method="post" id="posting-form" phx-submit="new-entry">
    <select name="identity" id="select_identity" phx-change="identity-change" class="bg-white dark:bg-black">
         <%= for {i, b62} <- @identities do %>
           <option value="<%= i %>"  <%= if @identity == i,  do: "selected" %>>
      <%= i<> " (" <> Catenary.short_id(b62)<>")" %>
           </option>
         <% end %>
       </select>
       <select name=log_id  class="bg-white dark:bg-black">
         <option value="360360">Journal</option>
       </select>
       <br/>
       <input class="bg-white dark:bg-black" type="text" name="title"/>
       <br/>
       <textarea class="bg-white dark:bg-black" name="body" rows="4" cols="50">
       </textarea>
       <hr/>
       <button phx-disable-with="posting..." type="submit">➲</button>
     </form>
      </div>
    """
  end
end
