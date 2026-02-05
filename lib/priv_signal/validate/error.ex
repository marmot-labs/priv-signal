defmodule PrivSignal.Validate.Error do
  @moduledoc false

  defstruct type: nil, flow_id: nil, module: nil, function: nil

  def missing_module(flow_id, module) do
    %__MODULE__{type: :missing_module, flow_id: flow_id, module: module}
  end

  def missing_function(flow_id, module, function) do
    %__MODULE__{type: :missing_function, flow_id: flow_id, module: module, function: function}
  end

  def format(%__MODULE__{type: :missing_module, module: module}) do
    "missing module #{format_module(module)}"
  end

  def format(%__MODULE__{type: :missing_function, module: module, function: function}) do
    "missing function #{format_module(module)}.#{format_function(function)}"
  end

  def format(error), do: inspect(error)

  defp format_module(nil), do: "<unknown module>"
  defp format_module(module), do: to_string(module)

  defp format_function(nil), do: "<unknown function>"
  defp format_function(function), do: to_string(function)
end
