defmodule Catenary.LogWriter do
  require Logger
  alias Catenary.{Indices, Preferences}

  @moduledoc """
  Functions for dealing with writing to the Baobab log store
  """
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
          try do
            %Baobab.Entry{payload: payload} =
              Baobab.log_entry(oa, oe, log_id: ol, clump_id: clump_id)

            {:ok, %{"title" => ot}, ""} = CBOR.decode(payload)
            ot
          rescue
            e ->
              Logger.debug("title decode fallback: #{Exception.message(e)}")
              ""
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

    fam_blocked = "challenge" in dl

    fam_data =
      if fam_blocked do
        %{"block_families" => all_family_names, "unblock_families" => []}
      else
        accepted_fams = Catenary.checkbox_expander(values, "family-")
        blocked_fams = Enum.reject(all_family_names, fn s -> s in accepted_fams end)

        case {blocked_fams, accepted_fams} do
          {[], []} -> %{}
          _ -> %{"block_families" => blocked_fams, "unblock_families" => accepted_fams}
        end
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

  # Backgammon challenge log (777)
  def new_entry(
        %{
          "log_id" => "777",
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
      |> append_log_for_socket(777, socket)

    Indices.update(:challenges)
    {Baobab.Identity.as_base62(a), l, e}
  end

  def new_entry(%{"log_id" => "777", "type" => "withdraw", "game_id" => game_id}, socket) do
    %Baobab.Entry{author: a, log_id: l, seqnum: e} =
      %{
        "type" => "withdraw",
        "game_id" => game_id,
        "published" => DateTime.utc_now() |> DateTime.to_string()
      }
      |> CBOR.encode()
      |> append_log_for_socket(777, socket)

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
        {:ok, a} -> a
        _ -> []
      end

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

  defp maybe_post_mentions(_, _, _, _), do: :ok

  defp append_log_for_socket(contents, log_id, socket) do
    Baobab.append_log(contents, Catenary.id_for_key(socket.assigns.identity),
      log_id: QuaggaDef.facet_log(log_id, socket.assigns.facet_id),
      clump_id: socket.assigns.clump_id
    )
  end
end
