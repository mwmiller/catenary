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
    <div class="min-w-full w-56 flex flex-col items-center">
      <div class="flex flex-col items-center gap-2 text-xl px-2 py-2 w-full">
        <div class="flex items-center gap-1">
          <%= if displayed_matches([:log, :profile], @displayed_info) do %>
            {post_button_for(:graph)}
            {post_button_for(:alias)}
          <% end %>
        </div>
        <div class="flex items-center gap-1">
          {for post_type <- [:journal, :image], do: post_button_for(post_type)}
        </div>
        <%= if displayed_matches([:log], @displayed_info) do %>
          <div class="flex items-center gap-1">
            {for post_type <- [:reply, :react, :tag, :mention], do: post_button_for(post_type)}
          </div>
        <% end %>
      </div>
      <div class="w-full flex justify-center mt-2 px-2 overflow-x-auto">
        {@lower_nav}
      </div>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :reply} = assigns) do
    ~H"""
    <div id="posting" class={panel_cls()}>
      <%= if displayed_matches([:log], @displayed_info) do %>
        {log_posting_form(assigns, :reply, source_title(@entry, @clump_id))}
      <% end %>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :journal} = assigns) do
    ~H"""
    <div id="posting" class={panel_cls()}>
      {log_posting_form(assigns, :journal, "")}
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :alias, :entry => {:tag, _}}), do: ""

  defp extra_nav(%{:extra_nav => :alias} = assigns) do
    ~H"""
    <div id="aliases" class={panel_cls()}>
      <form method="post" id="alias-form" phx-submit="new-entry" class="flex flex-col gap-3">
        <input type="hidden" name="log_id" value="53" />
        <%= if displayed_matches([:log], @displayed_info) do %>
          <input type="hidden" name="ref" value={Catenary.index_to_string(@entry)} />
        <% end %>
        <input type="hidden" name="whom" value={@whom} />
        <div class="flex items-center gap-2">
          {Display.scaled_avatar(@whom, 4, ["flex-none"]) |> Phoenix.HTML.raw()}
          <div class="min-w-0">
            <label for="alias" class={label_cls()}>Alias</label>
            <input class={input_cls()} name="alias" value={@ali} type="text" />
          </div>
        </div>
        {Display.log_submit_button()}
      </form>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :graph, :entry => {:tag, _}}), do: ""

  defp extra_nav(%{:extra_nav => :graph, :blocked => true} = assigns) do
    ~H"""
    <div id="block" class={panel_cls()}>
      {help_text(
        "You may unblock by submitting this form. It will publish a public log entry to that effect. Including a reason is optional."
      )}
      <form method="post" id="block-form" phx-submit="new-entry" class="flex flex-col gap-3 mt-3">
        <input type="hidden" name="log_id" value="1337" />
        <input type="hidden" name="action" value="unblock" />
        <%= if displayed_matches([:log], @displayed_info) do %>
          <input type="hidden" name="ref" value={Catenary.index_to_string(@recent.id)} />
        <% end %>
        <input type="hidden" name="whom" value={@whom} />
        <div class="flex items-center gap-2">
          {Display.scaled_avatar(@whom, 2) |> Phoenix.HTML.raw()}
          <span class="truncate">{Display.short_id(@whom, @aliases)}</span>
        </div>
        <div>
          <label for="reason" class={label_cls()}>Reason</label>
          <textarea class={input_cls()} id="reason" name="reason" rows="4"></textarea>
        </div>
        {Display.log_submit_button()}
      </form>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :graph} = assigns) do
    ~H"""
    <div id="block" class={panel_cls()}>
      {help_text(
        "Blocking will be published on a public log. This can have negative social implications. A block cannot disappear from your history."
      )}
      <form method="post" id="block-form" phx-submit="new-entry" class="flex flex-col gap-3 mt-3">
        <input type="hidden" name="log_id" value="1337" />
        <input type="hidden" name="action" value="block" />
        <%= if displayed_matches([:log], @displayed_info) do %>
          <input type="hidden" name="ref" value={Catenary.index_to_string(@entry)} />
        <% end %>
        <input type="hidden" name="whom" value={@whom} />
        <div class="flex items-center gap-2">
          {Display.scaled_avatar(@whom, 2) |> Phoenix.HTML.raw()}
          <span class="truncate">{Display.short_id(@whom, @aliases)}</span>
        </div>
        <div>
          <label for="reason" class={label_cls()}>Reason</label>
          <textarea class={input_cls()} id="reason" name="reason" rows="4"></textarea>
        </div>
        {Display.log_submit_button()}
      </form>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :profile} = assigns) do
    ~H"""
    <div id="profile-nav" class={panel_cls()}>
      <form method="post" id="profile-form" phx-submit="profile-update" class="flex flex-col gap-3">
        <div>
          <label for="name" class={label_cls()}>Name</label>
          <input
            type="text"
            class={input_cls()}
            id="name"
            name="name"
            value={Catenary.about_key(@identity, :name)}
          />
        </div>
        <div>
          <label for="description" class={label_cls()}>About</label>
          <textarea class={input_cls()} id="description" rows="8" name="description"><%= Catenary.about_key(@identity,"description") %></textarea>
        </div>
        <label class="flex items-center gap-2 text-sm">
          <input type="checkbox" class={checkbox_cls()} name="keep-avatar" checked /> Keep avatar
        </label>
        {Display.log_submit_button()}
      </form>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :mention} = assigns) do
    ~H"""
    <div id="mention" class={panel_cls()}>
      {help_text("You may only create mentions for those for whom you have set an alias.")}
      <form method="post" id="mention-form" phx-submit="new-entry" class="flex flex-col gap-3 mt-3">
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
    <div id="tags" class={panel_cls()}>
      <%= if displayed_matches([:log], @displayed_info) do %>
        <form method="post" id="tag-form" phx-submit="new-entry" class="flex flex-col gap-3">
          <input type="hidden" name="log_id" value="749" />
          <input type="hidden" name="ref" value={Catenary.index_to_string(@entry)} />
          {tag_inputs(4)}
          {Display.log_submit_button()}
        </form>
      <% end %>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :react} = assigns) do
    ~H"""
    <div id="reactions-nav" class={panel_cls()}>
      <%= if displayed_matches([:log], @displayed_info) do %>
        {help_text("Select one or more reactions to attach to this entry.")}
        <form method="post" id="reaction-form" phx-submit="new-entry" class="flex flex-col gap-2 mt-3">
          <input type="hidden" name="log_id" value="101" />
          <input type="hidden" name="ref" value={Catenary.index_to_string(@entry)} />
          <%= for e <- Catenary.Reactions.available() do %>
            <label class="flex items-center gap-2 text-sm">
              <input class={checkbox_cls()} type="checkbox" name={"reaction-" <> e} value={e} />
              {e}
            </label>
          <% end %>
          {Display.log_submit_button()}
        </form>
      <% end %>
    </div>
    """
  end

  defp extra_nav(%{:extra_nav => :image} = assigns) do
    ~H"""
    <div id="images-nav" class={panel_cls()}>
      <%= if displayed_matches(Catenary.image_logs(), @displayed_info) do %>
        <form id="set-avatar-form" phx-submit="new-entry" class="flex flex-col gap-3">
          <input type="hidden" name="log_id" value="360" />
          <input type="hidden" name="avatar" value={Catenary.index_to_string(@entry)} />
          <h4 class="text-sm font-semibold">Set this image as your avatar</h4>
          {Display.log_submit_button()}
        </form>
        <div class="my-3 border-t border-slate-200 dark:border-slate-700"></div>
      <% end %>
      <form
        id="imageupload-form"
        phx-submit="image-save"
        phx-change="image-validate"
        class="flex flex-col gap-3"
      >
        <label
          phx-drop-target={@uploads.image.ref}
          class="flex flex-col items-center justify-center gap-2 rounded-md border-2 border-dashed border-slate-300 dark:border-slate-600 bg-slate-50 dark:bg-slate-800 px-4 py-6 text-center cursor-pointer transition-colors hover:border-amber-500 dark:hover:border-amber-400 hover:bg-amber-50 dark:hover:bg-slate-700"
        >
          <span class="text-2xl leading-none text-amber-500 dark:text-amber-400">҂</span>
          <span class="text-sm text-slate-600 dark:text-slate-300">Click to choose or drop an image</span>
          <span class="text-xs text-slate-400 dark:text-slate-500">JPG, PNG or GIF</span>
          <.live_file_input upload={@uploads.image} class="sr-only" />
        </label>
        <%= for entry <- @uploads.image.entries do %>
          <div class="flex items-center gap-2 text-xs text-slate-600 dark:text-slate-300">
            <span class="truncate">{entry.client_name}</span>
          </div>
        <% end %>
        {Display.log_submit_button()}
      </form>
    </div>
    """
  end

  defp extra_nav(_), do: ""

  defp panel_cls,
    do: "rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-3"

  defp input_cls,
    do:
      "w-full rounded-md border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800 px-2 py-1 text-sm text-slate-900 dark:text-slate-100 transition-colors focus:outline-none focus:border-amber-500 dark:focus:border-amber-400 focus:ring-1 focus:ring-amber-500/60 dark:focus:ring-amber-400/60"

  defp checkbox_cls,
    do:
      "h-4 w-4 rounded border-slate-300 dark:border-slate-600 text-amber-500 dark:text-amber-400 focus:ring-1 focus:ring-amber-500/60 dark:focus:ring-amber-400/60"

  defp label_cls,
    do:
      "block text-[11px] font-medium uppercase tracking-wide text-slate-500 dark:text-slate-400 mb-1"

  defp help_cls, do: "text-xs leading-snug text-slate-500 dark:text-slate-400"

  defp help_text(text) do
    ~s(<p class="#{help_cls()}">#{text}</p>)
    |> Phoenix.HTML.raw()
  end

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
        ~s(<input type="hidden" name="ref" value="#{Catenary.index_to_string(entry)}" />)
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
      ~s(<form method="post" id="posting-form" phx-submit="new-entry" class="flex flex-col gap-3">),
      ~s(<input type="hidden" name="log_id" value="#{QuaggaDef.base_log(which)}" />),
      ref_input,
      ~s(<label for="title" class="#{label_cls()}">#{posting_icon(which)} Title</label>),
      ~s(<input class="#{input_cls()}" type="text" value="#{st}" name="title" />),
      ~s(<label for="body" class="#{label_cls()}">Body</label>),
      ~s(<textarea class="#{input_cls()}" name="body" rows="8"></textarea>),
      tag_html,
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
          Atom.to_string(which) <>
          "\" title=\"" <>
          posting_title(which) <>
          "\">" <>
          posting_icon(which) <> "</button>\n"

      false ->
        ""
    end
    |> Phoenix.HTML.raw()
  end

  defp posting_title(:graph), do: "Block/Unblock"
  defp posting_title(:alias), do: "Set Alias"
  defp posting_title(:tag), do: "Tag Entry"
  defp posting_title(:mention), do: "Mention"
  defp posting_title(:react), do: "React"
  defp posting_title(:reply), do: "Reply"
  defp posting_title(:journal), do: "New Journal Post"
  defp posting_title(:image), do: "New Image"

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

  defp tag_inputs(count), do: grouped_inputs(count, "tag", "# Tags")

  defp mention_inputs(count), do: grouped_inputs(count, "mention", "~ Mentions")

  defp grouped_inputs(count, name, label) do
    inputs =
      for n <- 0..(count - 1)//1 do
        qname = "\"" <> name <> Integer.to_string(n) <> "\""

        "<input class=\"" <>
          input_cls() <>
          "\" name=" <>
          qname <> " type=\"text\" />"
      end
      |> Enum.join("")

    Phoenix.HTML.raw("<label class=\"" <> label_cls() <> "\">" <> label <> "</label>" <> inputs)
  end
end
