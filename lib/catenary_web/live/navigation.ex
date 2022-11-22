defmodule Catenary.Live.Navigation do
  use Phoenix.LiveComponent

  @impl true

  def update(
        %{view: view, entry: entry, identity: identity, clump_id: clump_id} = assigns,
        socket
      ) do
    {whom, ali} = alias_info(entry, clump_id)
    on_log_entry = view == :entries && is_tuple(entry) && tuple_size(entry) == 3
    blocked = Catenary.blocked?(entry, clump_id)

    na =
      Map.merge(assigns, %{
        on_log_entry: on_log_entry,
        whom: whom,
        ali: ali,
        blocked: blocked
      })

    {:ok,
     assign(socket,
       view: view,
       entry: entry,
       clump_id: clump_id,
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
         <button value="unshown" phx-click="toview">!⃣</button>
         <%= if @on_log_entry do %>
           <button phx-click="toggle-block">⛒̟</button>
         <% end %>
         <button phx-click="toggle-stack">⇄</button>
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
        <%= log_posting_form(assigns, :reply, source_title(@entry, @clump_id)) %>
      <% end %>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :journal} = assigns) do
    ~L"""
    <div id="posting" class="font-sans">
        <%= log_posting_form(assigns, :journal, "") %>
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

  defp extra_nav(%{:extra_nav => :block, :entry => {:tag, _}}), do: ""

  defp extra_nav(%{:extra_nav => :block, :blocked => true} = assigns) do
    ~L"""
    <div id="block">
    <p class="my-5">You may unblock by submitting this form.  It will publish a 
    public log entry to that effect.  Including a reason is optional.</p>
    <br>
    <form method="post" id="block-form" phx-submit="new-entry">
     <input type="hidden" name="log_id" value="1337">
     <input type="hidden" name="action" value="unblock">
     <input type="hidden" name="ref" value="<%= Catenary.index_to_string(@entry) %>" />
     <input type="hidden" name="whom" value="<%= @whom %>" />
     <div class="w-100 grid grid-cols-3">
       <div>Unblock:</div><div><img src="<%= Catenary.identicon(@whom, 2) %>"></div><div><%= Catenary.short_id(@whom, @aliases) %></div>
       <div>Reason:</div><div class="grid-cols=2"><textarea class="bg-white dark:bg-black" name="reason" rows="4" cols="20"></textarea></div>
     </div>
     <hr/>
     <button phx-disable-with="𝄇" type="submit">➲</button>
    </form>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :block} = assigns) do
    ~L"""
    <div id="block">
      <p class="my-5">Blocking will be published on a public log.
      While this is worthwhile to help others on the network, it can have negative social implications.
      As with all log entries, a block cannot disappear from your history.</p>
      <br>
       <form method="post" id="block-form" phx-submit="new-entry">
         <input type="hidden" name="log_id" value="1337">
         <input type="hidden" name="action" value="block">
         <input type="hidden" name="ref" value="<%= Catenary.index_to_string(@entry) %>" />
         <input type="hidden" name="whom" value="<%= @whom %>" />
         <div class="w-100 grid grid-cols-3">
           <div>Block:</div><div><img src="<%= Catenary.identicon(@whom, 2) %>"></div><div><%= Catenary.short_id(@whom, @aliases) %></div>
           <div>Reason:</div><div class="grid-cols=2"><textarea class="bg-white dark:bg-black" name="reason" rows="4" cols="20"></textarea></div>
         </div>
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
         <%= tag_inputs(4) %>
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
  defp alias_info({a, l, e}, clump_id) when l in @alias_logs do
    try do
      %Baobab.Entry{payload: payload} = Baobab.log_entry(a, e, log_id: l, clump_id: clump_id)
      {:ok, data, ""} = CBOR.decode(payload)
      {data["whom"], data["alias"]}
    rescue
      _ -> {a, ""}
    end
  end

  defp alias_info({:profile, a}, _), do: {a, ""}
  defp alias_info({a, _, _}, _), do: {a, ""}
  defp alias_info(_, _), do: {"", ""}

  # show 
  defp source_title({a, l, e}, clump_id) do
    try do
      %Baobab.Entry{payload: payload} = Baobab.log_entry(a, e, log_id: l, clump_id: clump_id)

      {:ok, data, ""} = CBOR.decode(payload)
      data["title"]
    rescue
      _ -> ""
    end
  end

  defp source_title(_, _), do: ""

  defp log_posting_form(assigns, which, suggested_title) do
    ~L"""
    <form method="post" id="posting-form" phx-submit="new-entry">
      <input type="hidden" name="log_id" value="<%= QuaggaDef.base_log(which) %>">
      <% if which == :reply do %>
      <input type="hidden" name="ref" value="<%= Catenary.index_to_string(@entry) %>">
      <% end %>
      <br/>
      <input class="bg-white dark:bg-black" type="text" value="<%= suggested_title %>" name="title"/>
      <br/>
      <textarea class="bg-white dark:bg-black" name="body" rows="8" cols="35"></textarea>
      <p>
      <%= tag_inputs(2) %>
      <hr/>
      <button phx-disable-with="𝄇" type="submit">➲</button>
    </form>
    """
  end

  defp tag_inputs(count), do: make_tag_inputs(count, [])

  defp make_tag_inputs(0, acc), do: acc |> Enum.reverse() |> Enum.join("") |> Phoenix.HTML.raw()

  defp make_tag_inputs(n, acc) do
    less = n - 1
    qname = "\"tag" <> Integer.to_string(less) <> "\""

    make_tag_inputs(less, [
      "<label for=" <>
        qname <>
        ">#</label>" <>
        "<input class=\"bg-white dark:bg-black\" name=" <>
        qname <> " type=\"text\" size=\"16\" /><br/>"
      | acc
    ])
  end
end
