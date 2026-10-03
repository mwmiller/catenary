defmodule Catenary.LogWriter do
  require Logger
  alias Catenary.{Apps, Indices, Preferences}

  @moduledoc """
  Functions for dealing with writing to the Baobab log store
  """
  @challenge_log QuaggaDef.control_log(:backgammon)
  @challenge_log_str Integer.to_string(@challenge_log)

  @doc """
  Append a log with interface-provided values for the given Phoenix socket
  """
  def new_entry(values, socket)

  def new_entry(
        %{"body" => body, "log_id" => "360360", "title" => title} = vals,
        socket
      ) do
    # There will be more things to handle in short order, so this looks verbose
    # but it's probably necessary
    %Baobab.Entry{author: a, log_id: l, seqnum: e} =
      %{
        "body" => body,
        "title" => title,
        "published" => DateTime.utc_now() |> DateTime.to_string()
      }
      |> CBOR.encode()
      |> append_log_for_socket(360_360, socket)

    entry = {Baobab.Identity.as_base62(a), l, e}
    maybe_post_mentions(body, entry, socket, Preferences.get(:automention))
    maybe_tag(entry, vals, socket)
    Indices.update(:timelines)
    entry
  end

  def new_entry(%{"body" => body, "log_id" => "0"}, socket) do
    %Baobab.Entry{author: a, log_id: l, seqnum: e} = append_log_for_socket(body, 0, socket)
    {Baobab.Identity.as_base62(a), l, e}
  end

  def new_entry(
        %{
          "body" => body,
          "log_id" => "533",
          "ref" => ref,
          "title" => title
        } = vals,
        socket
      ) do
    # Only single parent references, but maybe multiple children
    # We get a tuple here, we'll get an array back from CBOR
    {oa, ol, oe} = Catenary.string_to_index(ref)
    clump_id = socket.assigns.clump_id

    t =
      case title do
        "" ->
          if ol
             |> QuaggaDef.base_log()
             |> QuaggaDef.log_def()
             |> Map.get(:type, "")
             |> is_binary() and
               ol
               |> QuaggaDef.base_log()
               |> QuaggaDef.log_def()
               |> Map.get(:type, "")
               |> String.starts_with?("image/") do
            Catenary.Display.entry_title(:image, %{})
          else
            try do
              %Baobab.Entry{payload: payload} =
                Baobab.log_entry(oa, oe, log_id: ol, clump_id: clump_id)

              {:ok, %{"title" => ot}, ""} = CBOR.decode(payload)
              ot
            rescue
              _ -> ""
            end
          end

        _ ->
          title
      end

    %Baobab.Entry{author: a, log_id: l, seqnum: e} =
      %{
        "body" => body,
        "references" => [[oa, ol, oe]],
        "title" => t,
        "published" => DateTime.utc_now() |> DateTime.to_string()
      }
      |> CBOR.encode()
      |> append_log_for_socket(533, socket)

    entry = {Baobab.Identity.as_base62(a), l, e}
    maybe_post_mentions(body, entry, socket, Preferences.get(:automention))
    maybe_tag(entry, vals, socket)
    Indices.update([:timelines, :references])
    entry
  end

  def new_entry(%{"log_id" => "53", "alias" => ali, "whom" => whom} = entry, socket) do
    references =
      case Map.get(entry, "ref") do
        nil -> []
        ref -> [Catenary.string_to_index(ref)]
      end

    %Baobab.Entry{author: a, log_id: l, seqnum: e} =
      %{
        "whom" => whom,
        "references" => references,
        "alias" => ali,
        "published" => DateTime.utc_now() |> DateTime.to_string()
      }
      |> CBOR.encode()
      |> append_log_for_socket(53, socket)

    Indices.update([:aliases, :references])
    {Baobab.Identity.as_base62(a), l, e}
  end

  def new_entry(
        %{
          "log_id" => "749",
          "ref" => ref,
          "tag0" => tag0,
          "tag1" => tag1,
          "tag2" => tag2,
          "tag3" => tag3
        },
        socket
      ) do
    references = Catenary.string_to_index(ref)

    case Enum.reject([tag0, tag1, tag2, tag3], fn s -> s == "" end) do
      [] ->
        references

      tags ->
        %{
          "references" => [references],
          "tags" => tags,
          "published" => DateTime.utc_now() |> DateTime.to_string()
        }
        |> CBOR.encode()
        |> append_log_for_socket(749, socket)

        Indices.update([:tags, :references])
        # Here we send them back to the referenced post which should now have tags applied
        # They can see the actual tagging post from the footer (or profile)
        references
    end
  end

  def new_entry(
        %{
          "log_id" => "121",
          "ref" => ref,
          "mention0" => mention0,
          "mention1" => mention1,
          "mention2" => mention2,
          "mention3" => mention3
        },
        socket
      ) do
    references = Catenary.string_to_index(ref)
    {:ok, aliases} = socket.assigns.aliases
    atok = Enum.reduce(aliases, %{}, fn {k, v}, a -> Map.put(a, v, k) end)

    valids =
      Enum.reduce([mention0, mention1, mention2, mention3], [], fn a, acc ->
        case Map.get(atok, a) do
          nil -> acc
          k -> [k | acc]
        end
      end)

    case valids do
      [] ->
        references

      mentions ->
        %{
          "references" => [references],
          "mentions" => mentions,
          "published" => DateTime.utc_now() |> DateTime.to_string()
        }
        |> CBOR.encode()
        |> append_log_for_socket(121, socket)

        Indices.update([:mentions, :references])
        # Here we send them back to the referenced post which should now have tags applied
        # They can see the actual tagging post from the footer (or profile)
        references
    end
  end

  def new_entry(
        %{
          "whom" => whom,
          "log_id" => "1337",
          "action" => action
        } = info,
        socket
      ) do
    ref =
      case info["ref"] do
        nil -> []
        val -> [Catenary.string_to_index(val)]
      end

    %Baobab.Entry{author: a, log_id: l, seqnum: e} =
      %{
        "whom" => whom,
        "references" => ref,
        "action" => action,
        "reason" => Map.get(info, "reason", ""),
        "published" => DateTime.utc_now() |> DateTime.to_string()
      }
      |> CBOR.encode()
      |> append_log_for_socket(1337, socket)

    Indices.update([:graph, :references])
    {Baobab.Identity.as_base62(a), l, e}
  end

  def new_entry(
        %{
          "log_id" => "1337",
          "listed" => direction
        } = values,
        socket
      ) do
    fl = QuaggaDef.log_defs() |> Enum.map(fn {_k, v} -> Atom.to_string(v.name) end)

    pl = Catenary.checkbox_expander(values, "log_name-")

    dl = fl |> Enum.reject(fn s -> s in pl end)

    arl =
      case direction do
        "accept" -> %{"accept" => pl, "reject" => dl}
        "reject" -> %{"accept" => dl, "reject" => pl}
      end

    all_family_names =
      QuaggaDef.families() |> Enum.map(fn {name, _tag} -> Atom.to_string(name) end)

    form_fams = Catenary.checkbox_expander(values, "family-")

    # A family is governed by its own control log, so rejecting that log
    # blocks the family whatever the form submitted, and accepting it leaves
    # the family to its checkbox.
    gated_fams =
      for {name, %{control_log: control}} <- QuaggaDef.family_defs(),
          Atom.to_string(control) in dl,
          do: Atom.to_string(name)

    blocked_fams = Enum.uniq(gated_fams ++ (all_family_names -- form_fams))

    unblocked_fams =
      Enum.filter(all_family_names, fn s -> s in form_fams and s not in blocked_fams end)

    fam_data =
      case {blocked_fams, unblocked_fams} do
        {[], []} -> %{}
        _ -> %{"block_families" => blocked_fams, "unblock_families" => unblocked_fams}
      end

    %Baobab.Entry{author: a, log_id: l, seqnum: e} =
      Map.merge(
        %{
          "action" => "logs",
          "published" => DateTime.utc_now() |> DateTime.to_string()
        },
        Map.merge(arl, fam_data)
      )
      |> CBOR.encode()
      |> append_log_for_socket(1337, socket)

    Indices.update(:graph)
    {Baobab.Identity.as_base62(a), l, e}
  end

  def new_entry(
        %{
          "ref" => ref,
          "log_id" => "101"
        } = values,
        socket
      ) do
    to = Catenary.string_to_index(ref)

    %{
      "references" => [to],
      "reactions" => Catenary.checkbox_expander(values, "reaction-"),
      "published" => DateTime.utc_now() |> DateTime.to_string()
    }
    |> CBOR.encode()
    |> append_log_for_socket(101, socket)

    Indices.update([:reactions, :references])
    to
  end

  def new_entry(%{"ref" => ref, "log_id" => "121", "mentions" => mentions}, socket) do
    to = Catenary.string_to_index(ref)

    %{
      "references" => [to],
      "mentions" => mentions,
      "published" => DateTime.utc_now() |> DateTime.to_string()
    }
    |> CBOR.encode()
    |> append_log_for_socket(121, socket)

    Indices.update([:mentions, :references])
    to
  end

  def new_entry(%{"log_id" => "360"} = values, socket) do
    # Shh, they can put any nonsense in any fields in here
    # We just mostly let it go. I don't dictate how other apps
    # might use this log... too much
    maybe_avatar =
      case Map.get(values, "avatar") do
        nil ->
          %{}

        istr ->
          case Catenary.string_to_index(istr) do
            :error -> %{}
            val -> %{"avatar" => val}
          end
      end

    # There is surely a better way to do this
    %Baobab.Entry{author: a} =
      values
      |> Map.drop(["log_id", "avatar"])
      |> Map.merge(maybe_avatar)
      |> Map.merge(%{"published" => DateTime.utc_now() |> DateTime.to_string()})
      |> CBOR.encode()
      |> append_log_for_socket(360, socket)

    me = Baobab.Identity.as_base62(a)
    Indices.update(:about)
    {:profile, me}
  end

  # Raw data handling, this should come from the definitions as well
  def new_entry(%{"log_id" => li, "data" => data}, socket)
      when li in ["8008", "8009", "8010"] do
    lid = String.to_integer(li)
    %Baobab.Entry{author: a, log_id: l, seqnum: e} = append_log_for_socket(data, lid, socket)
    Indices.update(:images)
    {Baobab.Identity.as_base62(a), l, e}
  end

  # Backgammon challenge log (the family's control log)
  def new_entry(
        %{
          "log_id" => @challenge_log_str,
          "type" => type,
          "family" => family
        } = values,
        socket
      )
      when type in ["challenge", "accept"] and family >= 1 and family <= 255 do
    %Baobab.Entry{author: a, log_id: l, seqnum: e} =
      %{
        "type" => type,
        "game_id" => Map.fetch!(values, "game_id"),
        "family" => family,
        "player" => Map.fetch!(values, "player"),
        "role" => Map.get(values, "role"),
        "to" => Map.get(values, "to"),
        "chain_spec" => Map.get(values, "chain_spec"),
        "chain_commit" => Map.get(values, "chain_commit"),
        "reveal" => Map.get(values, "reveal"),
        "published" => DateTime.utc_now() |> DateTime.to_string()
      }
      |> CBOR.encode()
      |> append_log_for_socket(@challenge_log, socket)

    Indices.update(:challenges)
    {Baobab.Identity.as_base62(a), l, e}
  end

  def new_entry(
        %{"log_id" => @challenge_log_str, "type" => "withdraw", "game_id" => game_id},
        socket
      ) do
    %Baobab.Entry{author: a, log_id: l, seqnum: e} =
      %{
        "type" => "withdraw",
        "game_id" => game_id,
        "published" => DateTime.utc_now() |> DateTime.to_string()
      }
      |> CBOR.encode()
      |> append_log_for_socket(@challenge_log, socket)

    Indices.update(:challenges)
    {Baobab.Identity.as_base62(a), l, e}
  end

  # Backgammon game play log (a derived log): the accepter's kickoff entry
  # opening the game's play stream. `log_id` is the full derived id — base
  # plus the writer's device facet — so this appends directly rather than via
  # `append_log_for_socket` (whose `facet_log` rejects derived bases).
  def new_entry(%{"log_id" => li, "type" => "play", "game_id" => game_id} = values, socket)
      when is_binary(li) do
    case Integer.parse(li) do
      {log_id, ""} ->
        %Baobab.Entry{author: a, log_id: l, seqnum: e} =
          %{
            "type" => "play",
            "game_id" => game_id,
            "family" => Map.fetch!(values, "family"),
            "player" => Map.fetch!(values, "player"),
            "role" => Map.get(values, "role"),
            "challenger" => Map.get(values, "challenger"),
            "chain_spec" => Map.get(values, "chain_spec"),
            "chain_commit" => Map.get(values, "chain_commit"),
            "challenger_commit" => Map.get(values, "challenger_commit"),
            "reveal" => Map.get(values, "reveal"),
            "game_base" => Map.get(values, "game_base"),
            "game_log_id" => Map.get(values, "game_log_id"),
            "published" => DateTime.utc_now() |> DateTime.to_string()
          }
          |> CBOR.encode()
          |> Baobab.append_log(Catenary.id_for_key(socket.assigns.identity),
            log_id: log_id,
            clump_id: socket.assigns.clump_id
          )

        {Baobab.Identity.as_base62(a), l, e}

      _ ->
        {:profile, socket.assigns.identity}
    end
  end

  # An opening-roll entry on the game's play log, appended to the full derived
  # id (base plus the writer's facet) just like the accepter's kickoff `play`
  # entry. After the write the challenges index refolds so the opponent's half
  # can close the round.
  def new_entry(%{"log_id" => li, "type" => "roll"} = values, socket)
      when is_binary(li) do
    case Integer.parse(li) do
      {log_id, ""} ->
        %Baobab.Entry{author: a, log_id: l, seqnum: e} =
          %{
            "type" => "roll",
            "game_id" => Map.fetch!(values, "game_id"),
            "player" => Map.fetch!(values, "player"),
            "round" => Map.fetch!(values, "round"),
            "reveals" => Map.fetch!(values, "reveals"),
            "r_cur" => Map.fetch!(values, "r_cur"),
            "r_next" => Map.fetch!(values, "r_next"),
            "note" => Map.get(values, "note", "")
          }
          |> CBOR.encode()
          |> Baobab.append_log(Catenary.id_for_key(socket.assigns.identity),
            log_id: log_id,
            clump_id: socket.assigns.clump_id
          )

        Catenary.Indices.update(:challenges)

        {Baobab.Identity.as_base62(a), l, e}

      _ ->
        {:profile, socket.assigns.identity}
    end
  end

  # A resign entry on a running game's play log, appended to the full derived
  # id (base plus the writer's device facet). After the write the challenges
  # index refolds so the game shows as finished with a winner.
  def new_entry(%{"log_id" => li, "type" => "resign"} = values, socket)
      when is_binary(li) do
    case Integer.parse(li) do
      {log_id, ""} ->
        %Baobab.Entry{author: a, log_id: l, seqnum: e} =
          %{
            "type" => "resign",
            "game_id" => Map.fetch!(values, "game_id"),
            "player" => Map.fetch!(values, "player"),
            "turn" => Map.fetch!(values, "turn"),
            "note" => Map.get(values, "note", "")
          }
          |> CBOR.encode()
          |> Baobab.append_log(Catenary.id_for_key(socket.assigns.identity),
            log_id: log_id,
            clump_id: socket.assigns.clump_id
          )

        Catenary.Indices.update(:challenges)

        {Baobab.Identity.as_base62(a), l, e}

      _ ->
        {:profile, socket.assigns.identity}
    end
  end

  # A turn entry on a running game's play log (a derived log), appended
  # directly to the full derived id (base plus the writer's device facet) just
  # like the accepter's kickoff `play` entry. After the write the challenges
  # index refolds so the board advances and the mover flips.
  def new_entry(%{"log_id" => li, "type" => "turn"} = values, socket)
      when is_binary(li) do
    case Integer.parse(li) do
      {log_id, ""} ->
        %Baobab.Entry{author: a, log_id: l, seqnum: e} =
          %{
            "type" => "turn",
            "game_id" => Map.fetch!(values, "game_id"),
            "player" => Map.fetch!(values, "player"),
            "turn" => Map.fetch!(values, "turn"),
            "roll" => Map.fetch!(values, "roll"),
            "moves" => Map.fetch!(values, "moves"),
            "r_cur" => Map.fetch!(values, "r_cur"),
            "r_next" => Map.fetch!(values, "r_next"),
            "reveals" => Map.fetch!(values, "reveals"),
            "note" => Map.get(values, "note", "")
          }
          |> CBOR.encode()
          |> Baobab.append_log(Catenary.id_for_key(socket.assigns.identity),
            log_id: log_id,
            clump_id: socket.assigns.clump_id
          )

        Catenary.Indices.update(:challenges)

        {Baobab.Identity.as_base62(a), l, e}

      _ ->
        {:profile, socket.assigns.identity}
    end
  end

  # Punt
  def new_entry(assigns, socket) do
    # This is a debug line I keep creating, so I am
    # going to leave it here for a while.
    Logger.debug(fn -> inspect(assigns) end)
    {:profile, socket.assigns.identity}
  end

  # What one human-mediated release may write. The artifact cap is the
  # plan's — 5 MB, human-approved — and the source cap is the playground's
  # own buffer cap, because sync is eager (§7.1): anything larger reaches
  # every peer that has not blocked this author, in the tab that is about to
  # render it.
  @max_artifact_bytes 5 * 1024 * 1024
  @max_source_bytes 256 * 1024

  @doc """
  Publish a playground buffer as an application: artifact, source, manifest
  and listing, in that order, each on its own log.

  `values` carries the words the author typed — `slug`, `title`,
  `description`, `version` — plus `source`, the buffer the playground
  holds. The module is built here rather than handed in by the caller so
  that compile, size caps and append are one choke point: every caller
  passes the same checks (§9.7).

  The appends run artifact → source → manifest → listing, and there is no
  rollback between them: a failure part way through leaves what was already
  written orphaned rather than referenced, because a reader reaches this
  release only through the listing, which is written last.

  Answers `{:ok, %{...}}` naming what landed, or `{:error, message}` for
  the trace line the panel shows.
  """
  @spec publish_app(map, map) ::
          {:ok,
           %{
             slug: binary,
             bytes: non_neg_integer,
             revision: pos_integer,
             listing: {binary, non_neg_integer, pos_integer},
             code: binary
           }}
          | {:error, binary}
  def publish_app(%{"slug" => slug, "source" => source} = values, socket) do
    with {:ok, slug} <- Apps.validate_slug(slug),
         :ok <- within(source, @max_source_bytes, "the buffer is over 256 KiB"),
         {:ok, %{wat: wat, wasm: wasm}} <- Apps.build_module(source),
         :ok <- within(wat, @max_source_bytes, "the source entry would be over 256 KiB"),
         :ok <- within(wasm, @max_artifact_bytes, "the artifact is over 5 MB") do
      append_release(slug, values, wat, wasm, socket)
    else
      {:error, :invalid_slug} -> {:error, "a slug is [a-z0-9-], up to 64 characters"}
      {:error, message} when is_binary(message) -> {:error, message}
    end
  rescue
    error -> {:error, "the log refused the release: " <> Exception.message(error)}
  end

  def publish_app(_values, _socket), do: {:error, "a publish needs a slug and a source"}

  defp append_release(slug, values, wat, wasm, socket) do
    published = DateTime.utc_now() |> DateTime.to_string()
    code = :crypto.hash(:sha256, wasm)

    %Baobab.Entry{} =
      append_kind(
        %{
          "v" => 1,
          "type" => "artifact",
          "slug" => slug,
          "code" => code,
          "bytes" => wasm,
          "published" => published
        },
        Apps.artifact_log(),
        socket
      )

    source_entry =
      append_kind(
        %{
          "v" => 1,
          "type" => "source",
          "slug" => slug,
          "code" => code,
          "text" => wat,
          "published" => published
        },
        Apps.source_log(),
        socket
      )

    manifest =
      %{
        "v" => 1,
        "type" => "manifest",
        "slug" => slug,
        "version" => release_version(values),
        "abi" => "catenary_v1",
        "features" => [],
        "artifact" => code,
        "source" => [source_entry.log_id, source_entry.seqnum],
        "published" => published
      }
      |> maybe_put("title", optional_text(values, "title"))
      |> maybe_put("description", optional_text(values, "description"))
      |> append_kind(Apps.manifest_log(), socket)

    listing =
      %{
        "type" => "listing",
        "family" => Apps.family(),
        "slug" => slug,
        # The listing names the manifest revision it points at, so a
        # re-listing and its manifest cannot come apart.
        "v" => manifest.seqnum,
        "published" => published
      }
      |> maybe_put("title", optional_text(values, "title"))
      |> maybe_put("description", optional_text(values, "description"))
      |> append_kind(Apps.control_log(), socket)

    Indices.update(:listings)

    {:ok,
     %{
       slug: slug,
       bytes: byte_size(wasm),
       revision: manifest.seqnum,
       listing: {Baobab.Identity.as_base62(listing.author), listing.log_id, listing.seqnum},
       code: code
     }}
  end

  defp append_kind(payload, base_log, socket) do
    payload
    |> CBOR.encode()
    |> append_log_for_socket(base_log, socket)
  end

  defp within(bytes, cap, message) when is_binary(bytes) do
    if byte_size(bytes) > cap, do: {:error, message}, else: :ok
  end

  # An unpublished-looking blank line from a form is left out of the entry
  # altogether: a viewer falls back to its own placeholder for a missing
  # title, but renders `untitled` for an empty one.
  defp optional_text(values, key) do
    case Map.get(values, key) do
      text when is_binary(text) and text != "" -> text
      _ -> nil
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp release_version(%{"version" => version}) when is_binary(version) and version != "",
    do: version

  defp release_version(_values), do: "0.1.0"

  defp maybe_tag(entry, %{"tag0" => "", "tag1" => ""}, _), do: entry

  defp maybe_tag(entry, %{"tag0" => tag0, "tag1" => tag1}, socket) do
    tag_entry =
      new_entry(
        %{
          "log_id" => "749",
          "ref" => Catenary.index_to_string(entry),
          "tag0" => tag0,
          "tag1" => tag1,
          "tag2" => "",
          "tag3" => ""
        },
        socket
      )

    Indices.update(:tags)
    tag_entry
  end

  defp maybe_tag(entry, _, _), do: entry

  defp maybe_post_mentions(text, parent, socket, true) do
    aliases =
      case socket.assigns.aliases do
        {:ok, a} -> Enum.to_list(a)
        _ -> []
      end

    maybe_mention(text, parent, socket, aliases)
  end

  defp maybe_post_mentions(_, _, _, _), do: :ok

  # No aliases set is a no-op, not a match-all. The pattern below is built by
  # joining the alias names, so with none it compiles to an empty regex, which
  # matches every string: publishing would then append a mention entry carrying
  # no mentions at all — a body-less entry beside every post.
  defp maybe_mention(_text, _parent, _socket, []), do: :ok

  defp maybe_mention(text, parent, socket, aliases) do
    {:ok, re} =
      Enum.reduce(aliases, [], fn {_k, v}, a -> ["(?:~" <> v <> ")" | a] end)
      |> Enum.join("|")
      |> Regex.compile()

    case Regex.scan(re, text) do
      [] ->
        :ok

      matches ->
        found =
          matches
          |> List.flatten()
          |> Enum.map(fn s -> String.replace(s, "~", "") end)

        mentioned =
          aliases
          |> Enum.filter(fn {_k, v} -> v in found end)
          |> Enum.map(fn {k, _v} -> k end)

        mentions_entry =
          new_entry(
            %{
              "log_id" => "121",
              "ref" => Catenary.index_to_string(parent),
              "mentions" => mentioned
            },
            socket
          )

        Indices.update(:mentions)
        mentions_entry
    end
  end

  defp append_log_for_socket(contents, log_id, socket) do
    Baobab.append_log(contents, Catenary.id_for_key(socket.assigns.identity),
      log_id: QuaggaDef.facet_log(log_id, socket.assigns.facet_id),
      clump_id: socket.assigns.clump_id
    )
  end
end
