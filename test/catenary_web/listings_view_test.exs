defmodule CatenaryWeb.ListingsViewTest do
  use CatenaryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Baobab.Identity
  alias Catenary.Live.EntryViewer
  alias Catenary.Preferences

  setup do
    # Navigating writes the view straight back to the preference store, and
    # that store outlives the suite. Put it back so the next test still
    # opens on the screen it always did.
    original = Preferences.get(:view)
    on_exit(fn -> Preferences.set(:view, original) end)
    :ok
  end

  test "the explorebar offers the listings view while the listing log is unblocked" do
    {:ok, view, _html} = live(build_conn(), "/")

    assert has_element?(view, "button[title=Listings]")
  end

  test "the listings view renders the listing explorer" do
    {:ok, view, _html} = live(build_conn(), "/")

    view |> element("button[title=Listings]") |> render_click()

    html = render(view)
    assert html =~ "Listings Explorer"
    assert html =~ "No listings."
  end

  # The control log persists across runs, so a listing published here has to
  # be withdrawn again or the next test to render the explorer sees it.
  defp publish(fields) do
    identity = Preferences.get(:identity)

    fields
    |> Map.put_new("published", DateTime.utc_now() |> DateTime.to_string())
    |> CBOR.encode()
    |> Baobab.append_log(Catenary.id_for_key(identity),
      log_id: QuaggaDef.facet_log(Catenary.Apps.control_log(), Preferences.get(:facet_id)),
      clump_id: Preferences.get(:clump_id)
    )
  end

  test "a listing entry gets its own card instead of a payload dump" do
    entry = publish(%{"type" => "listing", "family" => 2, "slug" => "card-app", "v" => 1})

    on_exit(fn ->
      publish(%{"type" => "delist", "family" => 2, "slug" => "card-app"})
      GenServer.call(:listings, :update)
    end)

    settings = [clump_id: Preferences.get(:clump_id), identity: Preferences.get(:identity)]
    ref = {Identity.as_base62(entry.author), entry.log_id, entry.seqnum}
    card = EntryViewer.extract(ref, settings)

    assert card["title"] == "⸤Listing: card-app⸣"
    # Plain text: the payload is peer-authored and reaches the template escaped.
    assert card["body"] == "card-app · app · v1"
    refute card["body"] =~ "%{"
    assert is_binary(card["published"])
  end

  test "a listing's description reaches both its card and its row" do
    entry =
      publish(%{
        "type" => "listing",
        "family" => 2,
        "slug" => "described-app",
        "v" => 1,
        "description" => "says hello, stores a value, renders a view"
      })

    GenServer.call(:listings, :update)

    on_exit(fn ->
      publish(%{"type" => "delist", "family" => 2, "slug" => "described-app"})
      GenServer.call(:listings, :update)
    end)

    settings = [clump_id: Preferences.get(:clump_id), identity: Preferences.get(:identity)]
    ref = {Identity.as_base62(entry.author), entry.log_id, entry.seqnum}

    assert EntryViewer.extract(ref, settings)["body"] ==
             "says hello, stores a value, renders a view"

    {:ok, view, _html} = live(build_conn(), "/")
    view |> element("button[title=Listings]") |> render_click()
    html = view |> element("#listings-explore-wrap") |> render()

    assert html =~ "says hello, stores a value, renders a view"
    assert html =~ "described-app"
    # The date is shown even when the listing has a description: it is the
    # field a sort or a filter will key on, so it is never the fallback.
    assert html =~ ~r/\d{4}-\d{2}-\d{2}/
  end

  test "a listing row never nests one button inside another" do
    publish(%{"type" => "listing", "family" => 2, "slug" => "shallow-row", "v" => 1})

    GenServer.call(:listings, :update)

    on_exit(fn ->
      publish(%{"type" => "delist", "family" => 2, "slug" => "shallow-row"})
      GenServer.call(:listings, :update)
    end)

    {:ok, view, _html} = live(build_conn(), "/")
    view |> element("button[title=Listings]") |> render_click()
    html = view |> element("#listings-explore-wrap") |> render()

    # Nested buttons are invalid HTML: the browser closes the outer one early,
    # which used to throw the author out of its row and drag the third column
    # out of the layout. The card is a div, and the two actions live in its
    # separate branches — neither can end up inside the other.
    assert :ok = buttons_are_siblings(html)
    assert html =~ "shallow-row"
  end

  defp buttons_are_siblings(html) do
    ~r/<button\b|<\/button>/
    |> Regex.scan(html)
    |> Enum.map(&hd/1)
    |> Enum.reduce_while(0, fn
      "</button>", 0 -> {:halt, {:stray_close, 0}}
      "</button>", depth -> {:cont, depth - 1}
      _open, depth when depth >= 1 -> {:halt, {:nested, depth}}
      _open, depth -> {:cont, depth + 1}
    end)
    |> case do
      0 -> :ok
      other -> other
    end
  end
end
