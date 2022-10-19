defmodule CatenaryWeb.ProfileController do
  use CatenaryWeb, :controller

  # This might seem like it should be part of the entry controller
  # It's a psuedo-entry at best. A horrible hack at worst
  # Maybe someday it will be better.
  def view(conn, %{"identity" => b62key} = _params) when byte_size(b62key) == 43 do
    live_render(conn, CatenaryWeb.Live,
      session: %{
        "view" => :entries,
        "entry" => {:profile, b62key}
      }
    )
  end
end
