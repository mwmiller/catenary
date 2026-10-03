defmodule Catenary.PublishAppTest do
  use ExUnit.Case, async: false

  alias Catenary.{Apps, LogWriter, Preferences}
  alias CatenaryWeb.Live

  # The write side of a release (§9.7 phase 2): compile, cap, append, index.
  # These touch the same store and the same `:listings` table the explorer
  # reads, so they are not async, and every test that leaves a listing
  # standing withdraws it again — kind entries have no delete, but a listing
  # nobody points at is invisible.

  @source ~S|on init:
  print(1)
|

  @broken ~S|on frob(x):
  print(1)
|

  @wat ~S|(module
  (memory (export "memory") 1)
)|

  defp socket do
    %{
      assigns: %{
        identity: Preferences.get(:identity),
        facet_id: Preferences.get(:facet_id),
        clump_id: Preferences.get(:clump_id)
      }
    }
  end

  defp publish(values), do: LogWriter.publish_app(Map.new(values), socket())

  # The key the listings table is keyed by: the signing key, base62, which
  # is what the index stores as a row's `pk`.
  defp my_pk, do: Baobab.Identity.as_base62(Catenary.id_for_key(Preferences.get(:identity)))

  # The facet this device writes to is the facet everything else in the app
  # reads from, so a test that looks for its own entries uses the same one.
  defp facet_log(base), do: QuaggaDef.facet_log(base, Preferences.get(:facet_id))

  defp entries(base) do
    author = Catenary.id_for_key(Preferences.get(:identity))
    clump = Preferences.get(:clump_id)
    log_id = facet_log(base)

    author
    |> Baobab.full_log(log_id: log_id, clump_id: clump)
    |> Enum.map(fn entry ->
      {:ok, data, ""} = CBOR.decode(entry.payload)
      {entry, data}
    end)
  end

  # The newest entry an author holds for one slug on a base — newest by
  # append order, which is what a second release of the same slug leaves
  # standing. Filtered by slug because every test in this file shares the
  # control log and the kind logs.
  defp last(base, slug) do
    base
    |> entries()
    |> Enum.filter(fn {_entry, data} -> data["slug"] == slug end)
    |> List.last()
  end

  defp seqnums do
    author = Catenary.id_for_key(Preferences.get(:identity))
    clump = Preferences.get(:clump_id)

    for base <- [Apps.artifact_log(), Apps.source_log(), Apps.manifest_log(), Apps.control_log()] do
      Baobab.max_seqnum(author, log_id: facet_log(base), clump_id: clump)
    end
  end

  # The retired kind sub-ids: no new entry may land on either — the WAT
  # rides the artifact and release metadata rides the listing — but older
  # stores still hold some, so the check is before/after, not "is empty".
  defp retired_kind_seqnums do
    author = Catenary.id_for_key(Preferences.get(:identity))
    clump = Preferences.get(:clump_id)

    for base <- [Apps.manifest_log(), Apps.source_log()] do
      Baobab.max_seqnum(author, log_id: facet_log(base), clump_id: clump)
    end
  end

  # A listing is what makes a release visible, so it is the half that has to
  # be taken back down; `GenServer.call` rather than the cast an index update
  # is, so the row is really gone before the next test opens the explorer.
  defp delist_on_exit(slug) do
    on_exit(fn ->
      %{"type" => "delist", "family" => Apps.family(), "slug" => slug}
      |> Map.put("published", DateTime.utc_now() |> DateTime.to_string())
      |> CBOR.encode()
      |> Baobab.append_log(Catenary.id_for_key(Preferences.get(:identity)),
        log_id: facet_log(Apps.control_log()),
        clump_id: Preferences.get(:clump_id)
      )

      GenServer.call(:listings, :update)
    end)
  end

  test "a release lands as artifact and listing" do
    slug = "publish-app"
    delist_on_exit(slug)
    retired = retired_kind_seqnums()

    assert {:ok, result} =
             publish(%{
               "slug" => slug,
               "title" => "Publish",
               "description" => "a test release",
               "version" => "1.2.3",
               "source" => @source
             })

    assert result.slug == slug
    assert result.bytes > 0
    assert result.version == "1.2.3"
    assert byte_size(result.code) == 32

    # The artifact entry is the whole release payload: the bytes and the
    # exact WAT they were built from together, under one `code` (one
    # traffic class — never the DSL that asked for it, decision #17).
    assert {_artifact_entry, artifact} = last(Apps.artifact_log(), slug)

    assert %{
             "type" => "artifact",
             "slug" => ^slug,
             "bytes" => bytes,
             "code" => code,
             "text" => wat
           } = artifact

    assert artifact["v"] == 1
    assert code == result.code
    assert :crypto.hash(:sha256, bytes) == code
    assert byte_size(bytes) == result.bytes
    assert String.starts_with?(wat, "(module")
    assert wat != @source

    # Neither retired kind base gets a new entry: the WAT rides the
    # artifact, and the release metadata rides the listing itself.
    assert retired_kind_seqnums() == retired

    # The listing is both the announcement and the release record: the
    # explorer reads it, and a reader resolves the bytes from the hash it
    # carries. There is no second metadata entry to keep in step.
    GenServer.call(:listings, :update)
    {_key, row} = List.first(:ets.lookup(:listings, {my_pk(), slug}))
    assert row.version == "1.2.3"
    assert row.family == Apps.family()
    assert row.description == "a test release"
    assert row.log_id == facet_log(Apps.control_log())

    assert {listing_entry, listing} = last(Apps.control_log(), slug)

    assert %{
             "type" => "listing",
             "slug" => ^slug,
             "version" => "1.2.3",
             "abi" => "catenary_v1",
             "features" => [],
             "artifact" => ^code,
             "title" => "Publish",
             "description" => "a test release"
           } = listing

    assert listing["family"] == Apps.family()
    refute Map.has_key?(listing, "v")
    assert listing["published"] == artifact["published"]
    assert listing_entry.seqnum == elem(result.listing, 2)
  end

  test "a WAT buffer is stored verbatim and built as it stands" do
    slug = "publish-wat-app"
    delist_on_exit(slug)

    assert {:ok, result} = publish(%{"slug" => slug, "source" => @wat})

    assert result.bytes > 0
    assert {_artifact_entry, %{"text" => text}} = last(Apps.artifact_log(), slug)
    assert text == @wat

    assert {_listing_entry, listing} = last(Apps.control_log(), slug)
    # A blank line from a form is left out of the entry rather than stored
    # as ""; a viewer falls back to its own placeholder for a missing title
    # but renders `untitled` for an empty one.
    refute Map.has_key?(listing, "title")
    refute Map.has_key?(listing, "description")
    assert listing["version"] == "0.1.0"
  end

  test "a slug that is not a slug writes nothing" do
    before = seqnums()

    assert {:error, message} = publish(%{"slug" => "Bad Slug", "source" => @source})
    assert message =~ "slug"

    assert seqnums() == before
  end

  test "a buffer that does not compile writes nothing" do
    before = seqnums()

    assert {:error, message} = publish(%{"slug" => "publish-broken", "source" => @broken})
    assert message =~ "line 1, col 4"

    assert seqnums() == before
  end

  test "a buffer over the source cap never reaches the compiler" do
    before = seqnums()
    huge = String.duplicate("x", 256 * 1024 + 1)

    assert {:error, message} = publish(%{"slug" => "publish-huge", "source" => huge})
    assert message == "the buffer is over 256 KiB"

    assert seqnums() == before
  end

  test "a publish without a slug and a source says so" do
    assert {:error, message} = publish(%{"source" => @source})
    assert message == "a publish needs a slug and a source"

    assert {:error, message} = publish(%{"slug" => "publish-empty"})
    assert message == "a publish needs a slug and a source"
  end

  # The panel is a message, not a call: the LiveView that holds the draft
  # joins its own buffer to the words and writes, and both outcomes come
  # back as a trace line the left rail can show.
  defp live_socket(source) do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        trace: [],
        trace_at: 0,
        source: source,
        identity: Preferences.get(:identity),
        facet_id: Preferences.get(:facet_id),
        clump_id: Preferences.get(:clump_id)
      }
    }
  end

  test "the panel's words and the buffer become a release and a trace line" do
    slug = "publish-panel-app"
    delist_on_exit(slug)

    words = %{
      "slug" => slug,
      "title" => "Panel",
      "description" => "from the panel",
      "version" => "2.0.0"
    }

    assert {:noreply, socket} =
             Live.handle_info({:playground_publish, words}, live_socket(@source))

    assert [%{"kind" => "publish", "detail" => detail}] = socket.assigns.trace
    assert detail =~ "published #{slug}"
    assert detail =~ "release v2.0.0"
    assert detail =~ "h'"
    assert detail =~ "bytes"

    assert {_listing_entry, listing} = last(Apps.control_log(), slug)
    assert listing["type"] == "listing"
    assert listing["slug"] == slug
    assert listing["version"] == "2.0.0"
    assert listing["description"] == "from the panel"
  end

  test "a buffer the panel cannot compile is a refusal in the trace" do
    words = %{"slug" => "publish-panel-broken"}

    assert {:noreply, socket} =
             Live.handle_info({:playground_publish, words}, live_socket(@broken))

    assert [%{"kind" => "publish", "detail" => detail}] = socket.assigns.trace
    assert detail =~ "publish refused: line 1, col 4"
  end

  # Reading a release back out of the store (§9.7 phase 2b): the viewer and
  # the module route ask for bytes and get them only through the newest
  # listing and the hash that listing names.
  defp append_kind(base, payload) do
    payload
    |> Map.put_new("published", DateTime.utc_now() |> DateTime.to_string())
    |> CBOR.encode()
    |> Baobab.append_log(Catenary.id_for_key(Preferences.get(:identity)),
      log_id: facet_log(base),
      clump_id: Preferences.get(:clump_id)
    )
  end

  test "a release resolves back to the bytes it was built from" do
    slug = "resolve-app"
    delist_on_exit(slug)

    assert {:ok, result} = publish(%{"slug" => slug, "title" => "Resolve", "source" => @source})

    clump = Preferences.get(:clump_id)
    pk = my_pk()

    assert Apps.released?(clump, pk, slug)
    refute Apps.released?(clump, pk, "resolve-never-published")
    # Another author holding nothing of this slug is not a release of it.
    refute Apps.released?(clump, String.duplicate("1", 43), slug)

    assert {:ok, %{bytes: bytes, text: text}} = Apps.release(clump, pk, slug)
    assert {:ok, listing} = Apps.listing(clump, pk, slug)
    assert listing["slug"] == slug
    assert listing["title"] == "Resolve"
    assert :crypto.hash(:sha256, bytes) == listing["artifact"]
    assert listing["artifact"] == result.code
    assert byte_size(bytes) == result.bytes
    # The release answers with the bytes and the WAT they were built from —
    # one artifact entry, both halves.
    assert {:ok, %{wat: expected}} = Apps.build_module(@source)
    assert text == expected
  end

  test "an artifact that does not hash to what the newest listing names is not the release" do
    slug = "resolve-hash-app"
    delist_on_exit(slug)

    assert {:ok, result} = publish(%{"slug" => slug, "source" => @source})

    # A second artifact on the same slug, written after the real one and
    # claiming a hash of its own: it does not hash to what the listing
    # names, so it is not this release's artifact.
    bogus = <<0, 1, 2, 3>>

    append_kind(Apps.artifact_log(), %{
      "v" => 1,
      "type" => "artifact",
      "slug" => slug,
      "code" => :crypto.hash(:sha256, bogus),
      "bytes" => bogus
    })

    clump = Preferences.get(:clump_id)
    assert {:ok, %{bytes: bytes}} = Apps.release(clump, my_pk(), slug)
    refute bytes == bogus
    assert :crypto.hash(:sha256, bytes) == result.code
  end

  test "a listing naming bytes nobody wrote is still a release, but resolves to nothing" do
    slug = "resolve-lost-app"
    delist_on_exit(slug)

    assert {:ok, _result} = publish(%{"slug" => slug, "source" => @source})

    append_kind(Apps.control_log(), %{
      "type" => "listing",
      "family" => Apps.family(),
      "slug" => slug,
      "version" => "9.9.9",
      "abi" => "catenary_v1",
      "features" => [],
      "artifact" => :crypto.hash(:sha256, "never written")
    })

    clump = Preferences.get(:clump_id)
    # The listing exists, so the slug is released...
    assert Apps.released?(clump, my_pk(), slug)
    # ...and the bytes it names are not in the store.
    assert {:error, :no_artifact} = Apps.release(clump, my_pk(), slug)
  end

  test "a listing for an ABI this host does not run is refused" do
    slug = "resolve-abi-app"
    delist_on_exit(slug)

    assert {:ok, _result} = publish(%{"slug" => slug, "source" => @source})

    append_kind(Apps.control_log(), %{
      "type" => "listing",
      "family" => Apps.family(),
      "slug" => slug,
      "version" => "1.0.0",
      "abi" => "catenary_v2",
      "features" => [],
      "artifact" => :crypto.hash(:sha256, "any bytes")
    })

    clump = Preferences.get(:clump_id)
    assert {:error, :unsupported_abi} = Apps.release(clump, my_pk(), slug)
  end

  test "a listing from before the fold resolves through its manifest" do
    slug = "resolve-legacy-app"
    delist_on_exit(slug)

    # The pre-fold shape, written by hand: artifact, manifest, then a
    # listing that points at the manifest by sequence number. Stores that
    # predate the fold still hold exactly this, and they keep resolving.
    assert {:ok, %{wat: wat, wasm: wasm}} = Apps.build_module(@source)
    code = :crypto.hash(:sha256, wasm)

    append_kind(Apps.artifact_log(), %{
      "v" => 1,
      "type" => "artifact",
      "slug" => slug,
      "code" => code,
      "bytes" => wasm,
      "text" => wat
    })

    append_kind(Apps.manifest_log(), %{
      "v" => 1,
      "type" => "manifest",
      "slug" => slug,
      "version" => "3.0.0",
      "abi" => "catenary_v1",
      "features" => [],
      "artifact" => code
    })

    manifest_seqnum =
      Baobab.max_seqnum(Catenary.id_for_key(Preferences.get(:identity)),
        log_id: facet_log(Apps.manifest_log()),
        clump_id: Preferences.get(:clump_id)
      )

    append_kind(Apps.control_log(), %{
      "type" => "listing",
      "family" => Apps.family(),
      "slug" => slug,
      "v" => manifest_seqnum
    })

    clump = Preferences.get(:clump_id)
    pk = my_pk()

    assert Apps.released?(clump, pk, slug)
    assert {:ok, %{bytes: ^wasm, text: ^wat}} = Apps.release(clump, pk, slug)

    # The listing itself still reads as the old shape — no record of its
    # own — which is what routes it back to the manifest it points at.
    assert {:ok, legacy} = Apps.listing(clump, pk, slug)
    refute Map.has_key?(legacy, "artifact")
    assert legacy["v"] == manifest_seqnum
  end
end
