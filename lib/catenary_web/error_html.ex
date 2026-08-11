defmodule CatenaryWeb.ErrorHTML do
  @moduledoc false
  use CatenaryWeb, :html

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end