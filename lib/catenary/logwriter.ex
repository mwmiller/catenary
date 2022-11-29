defmodule Catenary.LogWriter do
  @moduledoc """
  Functions for dealing with writing to the Baobab log store
  """
  @doc """
  Append a log with interface-provided values for the given Phoenix socket
  """
  def new_entry(values, socket)

  def new_entry(%{"body" => body, "log_id" => "360360", "title" => title} = vals, socket) do
    # There will be more things to handle in short order, so this looks verbose
    # but it's probably necessary
    %Baobab.Entry{author: a, log_id: l, seqnum: e} =
      %{"body" => body, "title" => title, "published" => Timex.now() |> DateTime.to_string()}
      |> CBOR.encode()
      |> append_log_for_socket(360_360, socket)

    entry = {Baobab.Identity.as_base62(a), l, e}
    Catenary.Indices.index_references([entry], socket.assigns.clump_id)
    maybe_tag(entry, vals, socket)
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
    Catenary.Indices.index_references([entry], socket.assigns.clump_id)
    maybe_tag(entry, vals, socket)
  end

  def new_entry(%{"log_id" => "53", "alias" => ali, "ref" => ref, "whom" => whom}, socket) do
    %Baobab.Entry{author: a, log_id: l, seqnum: e} =
      %{
        "whom" => whom,
        "references" => [Catenary.string_to_index(ref)],
        "alias" => ali,
        "published" => Timex.now() |> DateTime.to_string()
      }
      |> CBOR.encode()
      |> append_log_for_socket(53, socket)

    b62author = Baobab.Identity.as_base62(a)
    entry = {b62author, l, e}
    Catenary.Indices.index_aliases(b62author, socket.assigns.clump_id)
    Catenary.Indices.index_references([entry], socket.assigns.clump_id)
    entry
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
        %Baobab.Entry{author: a, log_id: l, seqnum: e} =
          %{
            "references" => [references],
            "tags" => tags,
            "published" => Timex.now() |> DateTime.to_string()
          }
          |> CBOR.encode()
          |> append_log_for_socket(749, socket)

        b62author = Baobab.Identity.as_base62(a)
        entry = {b62author, l, e}
        Catenary.Preferences.mark_entry(:shown, entry)
        Catenary.Indices.index_tags([entry], socket.assigns.clump_id)
        Catenary.Indices.index_references([entry], socket.assigns.clump_id)
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

    b62author = Baobab.Identity.as_base62(a)
    entry = {b62author, l, e}
    Catenary.SocialGraph.update_from_logs(b62author, socket.assigns.clump_id)
    Catenary.Indices.index_references([entry], socket.assigns.clump_id)
    entry
  end

  def new_entry(
        %{
          "ref" => ref,
          "log_id" => "101"
        } = values,
        socket
      ) do
    to = Catenary.string_to_index(ref)

    # Phoenix must be able to combine fieldsets and
    # yet here we are
    rl =
      values
      |> Map.to_list()
      |> Enum.reduce([], fn {k, v}, a ->
        r = String.split(k, "reaction-")

        case Enum.at(r, 1) == v do
          true -> [v | a]
          false -> a
        end
      end)

    %Baobab.Entry{author: a, log_id: l, seqnum: e} =
      %{
        "references" => [to],
        "reactions" => rl,
        "published" => Timex.now() |> DateTime.to_string()
      }
      |> CBOR.encode()
      |> append_log_for_socket(101, socket)

    b62author = Baobab.Identity.as_base62(a)
    entry = {b62author, l, e}
    Catenary.Preferences.mark_entry(:shown, entry)
    Catenary.Indices.index_reactions([entry], socket.assigns.clump_id)
    Catenary.Indices.index_references([entry], socket.assigns.clump_id)

    to
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
  end

  defp maybe_tag(entry, _, _), do: entry

  defp append_log_for_socket(contents, log_id, socket) do
    Baobab.append_log(contents, Catenary.id_for_key(socket.assigns.identity),
      log_id: QuaggaDef.facet_log(log_id, socket.assigns.facet_id),
      clump_id: socket.assigns.clump_id
    )
  end
end
