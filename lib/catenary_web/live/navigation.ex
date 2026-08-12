defmodule Catenary.Live.Navigation do
  @moduledoc """
  LiveComponent rendering the header, navigation controls, and current-entry context for a view.
  """
  use Phoenix.LiveComponent
  alias Catenary.{Display, Preferences}

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
    <div class="min-w-full">
      <div class="flex flex-wrap items-center justify-center gap-1 text-xl px-2 py-1">
        <div class="flex items-center gap-1">
          <button value="origin" phx-click="nav" title="Home">
            {Display.scaled_avatar(@identity, 2) |> Phoenix.HTML.raw()}
          </button>
          <%= if displayed_matches([:log, :profile], @displayed_info) do %>
            {post_button_for(:graph)}
            {post_button_for(:alias)}
          <% end %>
        </div>
        <div class="flex items-center gap-1">
          <button value="prev-author" phx-click="nav" title="Prev author">↥</button>
          <button value="prev-entry" phx-click="nav" title="Prev entry">⇜</button>
          <button phx-click="toggle-none" title="None">⍟</button>
          <button value="next-entry" phx-click="nav" title="Next entry">⇝</button>
          <button value="next-author" phx-click="nav" title="Next author">↧</button>
        </div>
        <div class="flex items-center gap-1">
          {for post_type <- [:journal, :image], do: post_button_for(post_type)}
          <%= if displayed_matches([:log], @displayed_info) do %>
            {for post_type <- [:reply, :react, :tag, :mention], do: post_button_for(post_type)}
          <% end %>
        </div>
      </div>
      {@lower_nav}
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :reply} = assigns) do
    ~H"""
    <div id="posting" class="font-sans">
      <%= if displayed_matches([:log], @displayed_info) do %>
        {log_posting_form(assigns, :reply, source_title(@entry, @clump_id))}
      <% end %>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :journal} = assigns) do
    ~H"""
    <div id="posting" class="font-sans">
      {log_posting_form(assigns, :journal, "")}
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
          <input type="hidden" name="ref" value={Catenary.index_to_string(@entry)} />
        <% end %>
        <input type="hidden" name="whom" value={@whom} />
        {Display.scaled_avatar(@whom, 4, ["mx-auto"]) |> Phoenix.HTML.raw()}
        <h3>{Display.short_id(@whom, @aliases)}</h3>
        <label for="alias">～</label>
        <input class="bg-white dark:bg-black" name="alias" value={@ali} type="text" size="16" />
        {Display.log_submit_button()}
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
          <input type="hidden" name="ref" value={Catenary.index_to_string(@recent.id)} />
        <% end %>
        <input type="hidden" name="whom" value={@whom} />
        <div class="w-100 grid grid-cols-3">
          <div>Unblock:</div>
          <div>{Display.scaled_avatar(@whom, 2)}</div>
          <div>{Display.short_id(@whom, @aliases)}</div>
          <div>Reason:</div>
          <div class="grid-cols=2">
            <textarea class="bg-white dark:bg-black" name="reason" rows="4" cols="20"></textarea>
          </div>
        </div>
        {Display.log_submit_button()}
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
          <input type="hidden" name="ref" value={Catenary.index_to_string(@entry)} />
        <% end %>
        <input type="hidden" name="whom" value={@whom} />
        <div class="w-100 grid grid-cols-3">
          <div>Block:</div>
          <div>{Display.scaled_avatar(@whom, 2) |> Phoenix.HTML.raw()}</div>
          <div>{Display.short_id(@whom, @aliases)}</div>
          <div>Reason:</div>
          <div class="grid-cols=2">
            <textarea class="bg-white dark:bg-black" name="reason" rows="4" cols="20"></textarea>
          </div>
        </div>
        {Display.log_submit_button()}
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
                value={Catenary.about_key(@identity, :name)}
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
        {Display.log_submit_button()}
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
          <input type="hidden" name="ref" value={Catenary.index_to_string(@entry)} />
        <% end %>
        {mention_inputs(4)}
        {Display.log_submit_button()}
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
          <input type="hidden" name="ref" value={Catenary.index_to_string(@entry)} />
          <p>
            {tag_inputs(4)}
          </p>
          {Display.log_submit_button()}
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
          <input type="hidden" name="ref" value={Catenary.index_to_string(@entry)} />
          <%= for e <- Catenary.Reactions.available() do %>
            <input class="bg-white dark:bg-black" type="checkbox" name={"reaction-" <> e} value={e} />
            {e}<br />
          <% end %>
          <br />
          {Display.log_submit_button()}
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
          <input type="hidden" name="avatar" value={Catenary.index_to_string(@entry)} />
          <h4>Set this image as your avatar</h4>
          {Display.log_submit_button()}
        </form>
        <br /><br />
      <% end %>
      <form id="imageupload-form" phx-submit="image-save" phx-change="image-validate">
        <h4>Publish a new image</h4>
        <.live_file_input upload={@uploads.image} />
        {Display.log_submit_button()}
      </form>
      <p class="py-5">Please be considerate with file sizes.</p>
    </div>
    """
  end

  defp extra_nav(_), do: ""

  @alias_logs QuaggaDef.logs_for_name(:alias)

  # We're looking at someone else's alias info, let's offer to use it
  defp alias_info({a, l, e}, clump_id) when l in @alias_logs do
    %Baobab.Entry{payload: payload} = Baobab.log_entry(a, e, log_id: l, clump_id: clump_id)
    {:ok, data, ""} = CBOR.decode(payload)
    {data["whom"], data["alias"]}
  rescue
    _ -> {a, ""}
  end

  defp alias_info({:profile, a}, _), do: {a, Catenary.about_key(a, "name")}
  defp alias_info({a, _, _}, _), do: {a, ""}
  defp alias_info(_, _), do: {"", ""}

  # show
  defp source_title({a, l, e}, clump_id) do
    %Baobab.Entry{payload: payload} = Baobab.log_entry(a, e, log_id: l, clump_id: clump_id)

    {:ok, data, ""} = CBOR.decode(payload)
    data["title"]
  rescue
    _ -> ""
  end

  defp source_title(_, _), do: ""

  defp log_posting_form(assigns, which, suggested_title) do
    entry = assigns.entry
    st = suggested_title

    ref_input =
      if which == :reply do
        ~s(<input type="hidden" name="ref" value="#{Catenary.index_to_string(entry)}" /><br />)
      else
        ""
      end

    tag_html =
      if Preferences.accept_log_name?(:tag) do
        tag_inputs(2)
      else
        ""
      end

    submit_btn = Display.log_submit_button()

    parts = [
      ~s(<form method="post" id="posting-form" phx-submit="new-entry">),
      ~s(<input type="hidden" name="log_id" value="#{QuaggaDef.base_log(which)}" />),
      ref_input,
      "<br /><label for=\"title\">#{posting_icon(which)}</label>",
      ~s(<input class="bg-white dark:bg-black" type="text" value="#{st}" name="title" />),
      "<br />",
      ~s(<textarea class="bg-white dark:bg-black" name="body" rows="8" cols="35"></textarea>),
      "<p>",
      tag_html,
      "</p>",
      submit_btn,
      "</form>"
    ]

    safe_binary =
      Enum.reduce(parts, "", fn
        {:safe, bin}, acc -> acc <> bin
        bin, acc when is_binary(bin) -> acc <> bin
      end)

    {:safe, safe_binary} |> Phoenix.HTML.raw()
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

  @doc """
  Returns true if any of the `list` of desired views matches the `displayed`
  view.

  `displayed` may be either a bare view atom (`:log`, `:entries`, …) or a
  tagged tuple (`{:log, _}`, `{:pseudo, _}`, `{:view, _}`); a bare `desired`
  matches its own tag OR the bare displayed value.
  """
  def displayed_matches(list, displayed), do: Enum.any?(list, &displayed_match(&1, displayed))

  defp displayed_match(desired, displayed) do
    same?(desired, displayed) or tagged_match?(desired, displayed)
  end

  defp same?(d, d), do: true
  defp same?(_, _), do: false

  defp tagged_match?(d, {tag, _inner}) when d in [:log, :pseudo, :view] and tag == d, do: true

  defp tagged_match?(d, {tag, inner})
       when d not in [:log, :pseudo, :view] and tag in [:log, :pseudo, :view] and d == inner,
       do: true

  defp tagged_match?(_, _), do: false

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
