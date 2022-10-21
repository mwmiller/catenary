defmodule Catenary.LogWriter do
  @moduledoc """
  Functions for dealing with writing to the Baobab log store
  """
  @doc """
  Append a log with interface-provided values for the given Phoenix socket
  """
  def new_entry(values, socket)

  def new_entry(%{"body" => body, "log_id" => "360360", "title" => title}, socket) do
    # There will be more things to handle in short order, so this looks verbose
    # but it's probably necessary
    %Baobab.Entry{author: a, log_id: l, seqnum: e} =
      %{"body" => body, "title" => title, "published" => Timex.now() |> DateTime.to_string()}
      |> CBOR.encode()
      |> append_log_for_socket(360_360, socket)

    entry = {Baobab.b62identity(a), l, e}
    Catenary.Indices.index_references([entry], socket.assigns.clump_id)
    entry
  end

  def new_entry(%{"body" => body, "log_id" => "0"}, socket) do
    %Baobab.Entry{author: a, log_id: l, seqnum: e} = append_log_for_socket(body, 0, socket)
    {Baobab.b62identity(a), l, e}
  end

  def new_entry(
        %{
          "body" => body,
          "log_id" => "533",
          "ref" => ref,
          "title" => title
        },
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

            {:ok, %{"title" => t}, ""} = CBOR.decode(payload)

            case t do
              <<"Re: ", _::binary>> -> t
              _ -> "Re: " <> t
            end
          rescue
            _ -> "Re: other post"
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

    entry = {Baobab.b62identity(a), l, e}
    Catenary.Indices.index_references([entry], socket.assigns.clump_id)
    entry
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

    b62author = Baobab.b62identity(a)
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
    tags = Enum.reject([tag0, tag1, tag2, tag3], fn s -> s == "" end)
    references = Catenary.string_to_index(ref)

    %Baobab.Entry{author: a, log_id: l, seqnum: e} =
      %{
        "references" => [references],
        "tags" => tags,
        "published" => Timex.now() |> DateTime.to_string()
      }
      |> CBOR.encode()
      |> append_log_for_socket(749, socket)

    b62author = Baobab.b62identity(a)
    entry = {b62author, l, e}
    Catenary.Indices.index_tags([entry], socket.assigns.clump_id)
    Catenary.Indices.index_references([entry], socket.assigns.clump_id)
    entry
  end

  # Punt
  def new_entry(_, socket), do: {:profile, socket.assigns.identity}

  defp append_log_for_socket(contents, log_id, socket) do
    Baobab.append_log(contents, Catenary.id_for_key(socket.assigns.identity),
      log_id: QuaggaDef.facet_log(log_id, socket.assigns.facet_id),
      clump_id: socket.assigns.clump_id
    )
  end
end
