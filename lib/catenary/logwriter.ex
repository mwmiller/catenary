defmodule Catenary.LogWriter do
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
      %{"body" => body, "title" => title, "published" => Timex.now() |> DateTime.to_string()}
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
            _ -> ""
          end

        _ ->
          title
      end

    %Baobab.Entry{author: a, log_id: l, seqnum: e} =
      %{
        "body" => body,
        "references" => [[oa, ol, oe]],
        "title" => t,
        "published" => Timex.now() |> DateTime.to_string()
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
        "published" => Timex.now() |> DateTime.to_string()
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
          "published" => Timex.now() |> DateTime.to_string()
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
          "published" => Timex.now() |> DateTime.to_string()
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
          "ref" => ref,
          "whom" => whom,
          "log_id" => "1337",
          "reason" => reason,
          "action" => action
        },
        socket
      ) do
    %Baobab.Entry{author: a, log_id: l, seqnum: e} =
      %{
        "whom" => whom,
        "references" => [Catenary.string_to_index(ref)],
        "action" => action,
        "reason" => reason,
        "published" => Timex.now() |> DateTime.to_string()
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
    # We want to know about which logs we knew at the time of
    # message creation, that way we don't need to make suppositions at 
    # message read time
    fl = QuaggaDef.log_defs() |> Enum.map(fn {_k, v} -> Atom.to_string(v.name) end)

    pl = Catenary.checkbox_expander(values, "log_name-")

    dl = fl |> Enum.reject(fn s -> s in pl end)

    arl =
      case direction do
        "accept" -> %{"accept" => pl, "reject" => dl}
        "reject" -> %{"accept" => dl, "reject" => pl}
      end

    %Baobab.Entry{author: a, log_id: l, seqnum: e} =
      Map.merge(
        %{
          "action" => "logs",
          "published" => Timex.now() |> DateTime.to_string()
        },
        arl
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
      "published" => Timex.now() |> DateTime.to_string()
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
      "published" => Timex.now() |> DateTime.to_string()
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
      |> Map.merge(%{"published" => Timex.now() |> DateTime.to_string()})
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

  # Punt
  def new_entry(assigns, socket) do
    # This is a debug line I keep creating, so I am
    # going to leave it here for a while.
    IO.inspect(assigns)
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
          Enum.reduce(aliases, [], fn {k, v}, a ->
            case v in found do
              true ->
                [k | a]

              false ->
                a
            end
          end)

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
