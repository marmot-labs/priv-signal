defmodule PrivSignal.Validate.Result do
  @moduledoc """
  Struct representing validation status and errors for a config section.
  """

  defstruct flow_id: nil, status: :ok, errors: []

  def ok?(%__MODULE__{status: :ok}), do: true
  def ok?(_), do: false
end
