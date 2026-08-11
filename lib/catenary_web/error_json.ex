defmodule CatenaryWeb.ErrorJSON do
  @moduledoc false
  use CatenaryWeb, :html

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end