defmodule PrivSignal.Validate.Result do
  @moduledoc false

  defstruct flow_id: nil, status: :ok, errors: []

  def ok?(%__MODULE__{status: :ok}), do: true
  def ok?(_), do: false
end
