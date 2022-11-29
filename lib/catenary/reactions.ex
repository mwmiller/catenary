defmodule Catenary.Reactions do
  @moduledoc """
  Helper functions for dealing with the joy which is reactions
  """

  # We're not going to restrict what other might send us for display
  # We are, however, only going to provide limited options for producing
  # reaction messages. 
  # I hope not to map these with keys.  I don't want to produce even implied
  # canonical interpretations. Hopefully I can use the values for the names in
  # any "web" forms.
  @producible ["🫖", "💎", "🦓", "⚽️", "💧", "🚦", "🌍"]

  def available(), do: @producible
end
