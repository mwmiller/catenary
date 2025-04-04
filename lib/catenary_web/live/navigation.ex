defmodule Catenary.Live.Navigation do
  use Phoenix.LiveComponent
  alias Catenary.{Preferences, Display}

  @impl true

  def update(
        %{view: view, entry: entry, identity: identity, clump_id: clump_id} = assigns,
        socket
      ) do
    {whom, ali} = alias_info(entry, clump_id)

    displayed_info =
      case {view, entry} do
        {:entries, {_a, l, _e}} ->
          %{name: n} = QuaggaDef.log_def(l)
          {:log, n}

        {:entries, {pseudo, _}} when is_atom(pseudo) ->
          {:pseudo, pseudo}

        {:view, view} when is_atom(view) ->
          {:view, view}

        _ ->
          {:unknown, :unknown}
      end

    blocked = Catenary.blocked?(entry, clump_id)

    na =
      Map.merge(assigns, %{
        view: view,
        displayed_info: displayed_info,
        identity: identity,
        whom: whom,
        ali: ali,
        blocked: blocked
      })

    {:ok,
     assign(socket,
       view: view,
       entry: entry,
       clump_id: clump_id,
       displayed_info: displayed_info,
       identity: identity,
       lower_nav: extra_nav(na)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="align-top min-w-full">
      <div class="flex flex-row-3 text-xl">
        <div class="flex-auto p-1 text-center">
          <button value="origin" phx-click="nav">
            <%= Display.scaled_avatar(@identity, 2) |> Phoenix.HTML.raw() %>
          </button>
          <%= if displayed_matches([:log, :profile], @displayed_info) do %>
            <%= post_button_for(:graph) %>
            <%= post_button_for(:alias) %>
          <% end %>
        </div>
        <div class="flex-auto p-1 text-center">
          <button value="prev-author" phx-click="nav">↥</button>
          <button value="prev-entry" phx-click="nav">⇜</button>
          <button phx-click="toggle-none">⍟</button>
          <button value="next-entry" phx-click="nav">⇝</button>
          <button value="next-author" phx-click="nav">↧</button>
        </div>
        <div class="flex-auto p-1 text-center">
          <%= for post_type <- [:journal, :image], do: post_button_for(post_type) %>
          <%= if displayed_matches([:log], @displayed_info) do %>
            <%= for post_type <- [:reply, :react, :tag, :mention], do: post_button_for(post_type) %>
          <% end %>
        </div>
      </div>
      <%= @lower_nav %>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :reply} = assigns) do
    ~H"""
    <div id="posting" class="font-sans">
      <%= if displayed_matches([:log], @displayed_info) do %>
        <%= log_posting_form(assigns, :reply, source_title(@entry, @clump_id)) %>
      <% end %>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :journal} = assigns) do
    ~H"""
    <div id="posting" class="font-sans">
      <%= log_posting_form(assigns, :journal, "") %>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :alias, :entry => {:tag, _}}), do: ""

  defp extra_nav(%{:extra_nav => :alias} = assigns) do
    ~H"""
    <div id="aliases">
      <form method="post" id="alias-form" phx-submit="new-entry">
        <input type="hidden" name="log_id" value="53" />
        <%= if displayed_matches([:log], @displayed_info) do %>
          <input type="hidden" name="ref" value="{ Catenary.index_to_string(@entry) }" />
        <% end %>
        <input type="hidden" name="whom" value="{ @whom }" />
        <%= Display.scaled_avatar(@whom, 4, ["mx-auto"]) |> Phoenix.HTML.raw() %>
        <h3><%= Display.short_id(@whom, @aliases) %></h3>
        <label for="alias">～</label>
        <input class="bg-white dark:bg-black" name="alias" value="{ @ali }" type="text" size="16" />
        <%= Display.log_submit_button() %>
      </form>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :graph, :entry => {:tag, _}}), do: ""

  defp extra_nav(%{:extra_nav => :graph, :blocked => true} = assigns) do
    ~H"""
    <div id="block">
      <p class="my-5">You may unblock by submitting this form.  It will publish a
        public log entry to that effect.  Including a reason is optional.</p>
      <br />
      <form method="post" id="block-form" phx-submit="new-entry">
        <input type="hidden" name="log_id" value="1337" />
        <input type="hidden" name="action" value="unblock" />
        <%= if displayed_matches([:log], @displayed_info) do %>
          <input type="hidden" name="ref" value="{Catenary.index_to_string(@recent.id)}" />
        <% end %>
        <input type="hidden" name="whom" value="{ @whom }" />
        <div class="w-100 grid grid-cols-3">
          <div>Unblock:</div>
          <div><%= Display.scaled_avatar(@whom, 2) %></div>
          <div><%= Display.short_id(@whom, @aliases) %></div>
          <div>Reason:</div>
          <div class="grid-cols=2">
            <textarea class="bg-white dark:bg-black" name="reason" rows="4" cols="20"></textarea>
          </div>
        </div>
        <%= Display.log_submit_button() %>
      </form>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :graph} = assigns) do
    ~H"""
    <div id="block">
      <p class="my-5">Blocking will be published on a public log.
        This can have negative social implications.
        A block cannot disappear from your history.</p>
      <br />
      <form method="post" id="block-form" phx-submit="new-entry">
        <input type="hidden" name="log_id" value="1337" />
        <input type="hidden" name="action" value="block" />
        <%= if displayed_matches([:log], @displayed_info) do %>
          <input type="hidden" name="ref" value="{Catenary.index_to_string(@entry)}" />
        <% end %>
        <input type="hidden" name="whom" value="{ @whom }" />
        <div class="w-100 grid grid-cols-3">
          <div>Block:</div>
          <div><%= Display.scaled_avatar(@whom, 2) |> Phoenix.HTML.raw() %></div>
          <div><%= Display.short_id(@whom, @aliases) %></div>
          <div>Reason:</div>
          <div class="grid-cols=2">
            <textarea class="bg-white dark:bg-black" name="reason" rows="4" cols="20"></textarea>
          </div>
        </div>
        <%= Display.log_submit_button() %>
      </form>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :profile} = assigns) do
    ~H"""
    <div id="profile-nav">
      <form method="post" id="profile-form" phx-submit="profile-update">
        <table>
          <tr>
            <td>Name:</td>
            <td>
              <input
                type="text"
                class="bg-white dark:bg-black"
                name="name"
                value="{ Catenary.about_key(@identity, :name) }"
              />
            </td>
          </tr>
          <tr>
            <td>About:</td>
            <td>
              <textarea class="bg-white dark:bg-black" rows="11" cols="31" name="description"><%= Catenary.about_key(@identity,"description") %></textarea>
            </td>
          </tr>
          <tr>
            <td>Avatar:</td>
            <td>
              <input type="checkbox" class="bg-white dark:bg-black" name="keep-avatar" checked /> keep
            </td>
          </tr>
        </table>
        <%= Display.log_submit_button() %>
      </form>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :mention} = assigns) do
    ~H"""
    <div id="mention">
      <p class="my-5">You may only create mentions for those for whom you have set an alias</p>
      <br />
      <form method="post" id="mention-form" phx-submit="new-entry">
        <input type="hidden" name="log_id" value="121" />
        <%= if displayed_matches([:log], @displayed_info) do %>
          <input type="hidden" name="ref" value="{ Catenary.index_to_string(@entry) }" />
        <% end %>
        <%= mention_inputs(4) %>
        <%= Display.log_submit_button() %>
      </form>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :tag, :entry => {:tag, _}}), do: ""

  defp extra_nav(%{:extra_nav => :tag} = assigns) do
    ~H"""
    <div id="tags">
      <%= if displayed_matches([:log], @displayed_info) do %>
        <form method="post" id="tag-form" phx-submit="new-entry">
          <input type="hidden" name="log_id" value="749" />
          <input type="hidden" name="ref" value="{ Catenary.index_to_string(@entry) }" />
          <p>
            <%= tag_inputs(4) %>
          </p>
          <%= Display.log_submit_button() %>
        </form>
      <% end %>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :react} = assigns) do
    ~H"""
    <div id="reactions-nav" class="flex flex-row 5 mt-20">
      <%= if displayed_matches([:log], @displayed_info) do %>
        <form method="post" id="reaction-form" phx-submit="new-entry">
          <input type="hidden" name="log_id" value="101" />
          <input type="hidden" name="ref" value="{ Catenary.index_to_string(@entry) }" />
          <%= for e <- Catenary.Reactions.available() do %>
            <input class="bg-white dark:bg-black" type="checkbox" name="reaction-{ e }" value="{ e }" />
            <%= e %><br />
          <% end %>
          <br />
          <%= Display.log_submit_button() %>
        </form>
      <% end %>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :image} = assigns) do
    ~H"""
    <div id="images-nav" class="mt-10">
      <%= if displayed_matches(Catenary.image_logs(), @displayed_info) do %>
        <form id="set-avatar-form" phx-submit="new-entry">
          <input type="hidden" name="log_id" value="360" />
          <input type="hidden" name="avatar" value="{ Catenary.index_to_string(@entry) }" />
          <h4>Set this image as your avatar</h4>
          <%= Display.log_submit_button() %>
        </form>
        <br /><br />
      <% end %>
      <form id="imageupload-form" phx-submit="image-save" phx-change="image-validate">
        <h4>Publish a new image</h4>
        <%= live_file_input(@uploads.image) %>
        <%= Display.log_submit_button() %>
      </form>
      <p class="py-5">Please be considerate with file sizes.</p>
    </div>
    """
  end

  defp extra_nav(_), do: ""

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

  defp alias_info({:profile, a}, _), do: {a, Catenary.about_key(a, "name")}
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
    assigns = assign(assigns, st: suggested_title, which: which)

    ~H"""
    <form method="post" id="posting-form" phx-submit="new-entry">
      <input type="hidden" name="log_id" value="{ QuaggaDef.base_log(which) }" />
      <%= if @which == :reply do %>
        <input type="hidden" name="ref" value="{ Catenary.index_to_string(@entry) }" />
      <% end %>
      <br />
      <label for="title"><%= posting_icon(@which) %></label>
      <input class="bg-white dark:bg-black" type="text" value="{ @st }" name="title" />
      <br />
      <textarea class="bg-white dark:bg-black" name="body" rows="8" cols="35"></textarea>
      <p>
        <%= if Preferences.accept_log_name?(:tag), do: tag_inputs(2) %>
      </p>
      <%= Display.log_submit_button() %>
    </form>
    """
  end

  defp post_button_for(which) do
    case Preferences.accept_log_name?(which) do
      true ->
        "<button phx-click=\"toggle-" <>
          Atom.to_string(which) <> "\">" <> posting_icon(which) <> "</button>\n"

      false ->
        ""
    end
    |> Phoenix.HTML.raw()
  end

  defp posting_icon(:graph), do: "⛒̟"
  defp posting_icon(:alias), do: "~̟"
  defp posting_icon(:tag), do: "#̟"
  defp posting_icon(:mention), do: "∑̟"
  defp posting_icon(:react), do: "⌘̟"
  defp posting_icon(:reply), do: "↩︎̟"
  defp posting_icon(:journal), do: "✎̟"
  defp posting_icon(:image), do: "̟҂"

  defp displayed_matches(list, displayed), do: displayed_matches(list, displayed, false)

  defp displayed_matches([], _, false), do: false
  defp displayed_matches(_, _, true), do: true

  defp displayed_matches([this | rest], displayed, acc),
    do: displayed_matches(rest, displayed, acc or displayed_match(this, displayed))

  defp displayed_match(desired, displayed) do
    # This is intended to simplify checks elsewhere
    # It also might introduce some ambiguity when
    # the :view looks like an :entries type
    # If this bit you, feel free to curse at me.
    # You might resolve it by using a fully explicit check
    # Or you can improve the logic or naming
    case {desired, displayed} do
      {^desired, ^desired} -> true
      {:log, {:log, _}} -> true
      {:log, _} -> false
      {:pseudo, {:pseudo, _}} -> true
      {:pseudo, _} -> false
      {:view, {:view, _}} -> true
      {:view, _} -> false
      {^desired, {:log, ^desired}} -> true
      {^desired, {:pseudo, ^desired}} -> true
      {^desired, {:view, ^desired}} -> true
      _ -> false
    end
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

  defp mention_inputs(count), do: make_mention_inputs(count, [])

  defp make_mention_inputs(0, acc),
    do: acc |> Enum.reverse() |> Enum.join("") |> Phoenix.HTML.raw()

  defp make_mention_inputs(n, acc) do
    less = n - 1
    qname = "\"mention" <> Integer.to_string(less) <> "\""

    make_mention_inputs(less, [
      "<label for=" <>
        qname <>
        ">~</label>" <>
        "<input class=\"bg-white dark:bg-black\" name=" <>
        qname <> " type=\"text\" size=\"16\" /><br/>"
      | acc
    ])
  end
end
