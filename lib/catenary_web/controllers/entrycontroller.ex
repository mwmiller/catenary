defmodule CatenaryWeb.EntryController do
  use CatenaryWeb, :controller

  def view(conn, %{"index_format" => idx_string} = _params) do
    reentry(conn, Catenary.string_to_index(String.trim(idx_string)))
  end

  def view(conn, %{"identity" => id, "log_id" => lid, "seqnum" => seq} = _params) do
    reentry(conn, {id, String.to_integer(lid), String.to_integer(seq)})
  end

  defp reentry(conn, entry) do
    live_render(conn, CatenaryWeb.Live,
      session: %{
        "view" => :entries,
        "entry" => entry
      }
    )
  end
end
