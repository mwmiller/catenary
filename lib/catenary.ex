defmodule Catenary do
  @moduledoc """
  Catenary keeps the contexts that define your domain
  and business logic.
  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  def short_id(id), do: "~" <> String.slice(id, 0..15)

  def identicon(id, type, mag \\ 4) do
    b64 = Excon.ident(id, base64: true, type: type, magnification: mag)

    mime =
      case type do
        :png -> "image/png"
        :svg -> "image/svg+xml"
      end

    "data:" <> mime <> ";base64," <> b64
  end
end
