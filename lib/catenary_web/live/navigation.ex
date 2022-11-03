defmodule Catenary.Live.Navigation do
  use Phoenix.LiveComponent

  @impl true

  def update(%{view: view, entry: entry, identity: identity} = assigns, socket) do
    {whom, ali} = alias_info(entry)
    on_log_entry = view == :entries && is_tuple(entry) && tuple_size(entry) == 3

    na =
      Map.merge(assigns, %{
        on_log_entry: on_log_entry,
        whom: whom,
        ali: ali
      })

    {:ok,
     assign(socket,
       view: view,
       entry: entry,
       on_log_entry: on_log_entry,
       identity: identity,
       lower_nav: extra_nav(na)
     )}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div class="align-top min-w-full">
      <div class="flex flex-row-3 text-xl">
        <div class="flex-auto p-1 text-center">
         <button value="origin" phx-click="nav"><img src="<%= Catenary.identicon(@identity, 2) %>"></button>
         <button value="unshown" phx-click="toview">☇</button>
         <button phx-click="toggle-stack">⭤</button>
        </div>
        <div class="flex-auto p-1 text-center">
         <button value="prev-author" phx-click="nav">↥</button>
         <button value="prev-entry" phx-click="nav">⇜</button>
         <button value="next-entry" phx-click="nav">⇝</button>
         <button value="next-author" phx-click="nav">↧</button>
       </div>
       <div class="flex-auto p-1 text-center">
         <button phx-click="toggle-journal">✎̟</button>
       <%= if @on_log_entry do %>
        <button phx-click="toggle-reply">↺̟</button>
        <button phx-click="toggle-tags">#̟</button>
        <button phx-click="toggle-aliases">~̟</button>
       <% end %>
       </div>
     </div>
      <%= @lower_nav %>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :reply} = assigns) do
    ~L"""
    <div id="posting" class="font-sans">
      <%= if @on_log_entry do %>
        <h4>Post a Reply</h4>
        <%= log_posting_form(assigns, :reply) %>
      <% end %>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :journal} = assigns) do
    ~L"""
    <div id="posting" class="font-sans">
      <h4>Create Journal Entry</h4>
      <%= log_posting_form(assigns, :journal) %>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :aliases, :entry => {:tag, _}}), do: ""

  defp extra_nav(%{:extra_nav => :aliases} = assigns) do
    ~L"""
    <div id="aliases">
       <form method="post" id="alias-form" phx-submit="new-entry">
         <input type="hidden" name="log_id" value="53">
         <input type="hidden" name="ref" value="<%= Catenary.index_to_string(@entry) %>" />
         <input type="hidden" name="whom" value="<%= @whom %>" />
         <img class="mx-auto" src="<%= Catenary.identicon(@whom, 4) %>">
           <h3><%= Catenary.short_id(@whom, @aliases) %></h3>
         <label for="alias">～</label>
         <input class="bg-white dark:bg-black" name="alias" value="<%= @ali %>" type="text" size="16" />
         <hr/>
         <button phx-disable-with="𝄇" type="submit">➲</button>
       </form>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :tags, :entry => {:tag, _}}), do: ""

  defp extra_nav(%{:extra_nav => :tags} = assigns) do
    ~L"""
    <div id="tags">
      <%= if @on_log_entry do %>
       <form method="post" id="tag-form" phx-submit="new-entry">
         <input type="hidden" name="log_id" value="749">
         <input type="hidden" name="ref" value="<%= Catenary.index_to_string(@entry) %>">
         <p>
           <%= for n <- 0..3 do %>
             <label for="tag<%= n %>">#</label>
        <input class="bg-white dark:bg-black" name="tag<%= n %>" type="text" size="16" /><br/>
        <% end %>
         <hr/>
         <button phx-disable-with="𝄇" type="submit">➲</button>
       </form>
      <% end %>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :stack} = assigns) do
    ~L"""
    <div id="stack-nav" class="flex flex-row 5 mt-20">
       <div class="flex-auto p-4 m-1 text-xl text-center <%= stack_color(@entry_back) %>" phx-click="nav-backward">⤶</div>
       <div class="flex-auto p-4 m-1 text-xl text-center <%= stack_color(@entry_fore) %>" phx-click="nav-forward">⤷</div>
    </div>
    """
  end

  defp extra_nav(_), do: ""

  defp stack_color([]), do: "bg-zinc-50 dark:bg-gray-800"
  defp stack_color(_), do: "bg-zinc-100 dark:bg-gray-900"

  @alias_logs QuaggaDef.logs_for_name(:alias)

  # We're looking at someone else's alias info, let's offer to use it
  defp alias_info({a, l, e}) when l in @alias_logs do
    try do
      %Baobab.Entry{payload: payload} = Baobab.log_entry(a, e, log_id: l)
      {:ok, data, ""} = CBOR.decode(payload)
      {data["whom"], data["alias"]}
    rescue
      _ -> {a, ""}
    end
  end

  defp alias_info({:profile, a}), do: {a, ""}
  defp alias_info({a, _, _}), do: {a, ""}
  defp alias_info(_), do: {"", ""}

  defp log_posting_form(assigns, which) do
    ~L"""
    <form method="post" id="posting-form" phx-submit="new-entry">
      <input type="hidden" name="log_id" value="<%= QuaggaDef.base_log(which) %>">
      <input type="hidden" name="ref" value="<%= Catenary.index_to_string(@entry) %>">
      <br/>
      <input class="bg-white dark:bg-black" type="text" name="title"/>
      <br/>
      <textarea class="bg-white dark:bg-black" name="body" rows="8" cols="35"></textarea>
      <hr/>
      <button phx-disable-with="𝄇" type="submit">➲</button>
    </form>
    """
  end
end
