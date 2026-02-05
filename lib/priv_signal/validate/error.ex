defmodule PrivSignal.Validate.Error do
  @moduledoc false

  defstruct type: nil,
            flow_id: nil,
            module: nil,
            function: nil,
            from: nil,
            to: nil,
            caller: nil,
            arity: nil,
            candidates: []

  def missing_module(flow_id, module) do
    %__MODULE__{type: :missing_module, flow_id: flow_id, module: module}
  end

  def missing_function(flow_id, module, function) do
    %__MODULE__{type: :missing_function, flow_id: flow_id, module: module, function: function}
  end

  def missing_edge(flow_id, from_module, from_function, to_module, to_function) do
    %__MODULE__{
      type: :missing_edge,
      flow_id: flow_id,
      from: %{module: from_module, function: from_function},
      to: %{module: to_module, function: to_function}
    }
  end

  def ambiguous_call(flow_id, caller_module, caller_function, fun_name, arity, candidates) do
    %__MODULE__{
      type: :ambiguous_call,
      flow_id: flow_id,
      caller: %{module: caller_module, function: caller_function},
      function: fun_name,
      arity: arity,
      candidates: candidates
    }
  end

  def format(%__MODULE__{type: :missing_module, module: module}) do
    "missing module #{format_module(module)}"
  end

  def format(%__MODULE__{type: :missing_function, module: module, function: function}) do
    "missing function #{format_module(module)}.#{format_function(function)}"
  end

  def format(%__MODULE__{type: :missing_edge, from: from, to: to}) do
    "missing call edge #{format_module(from.module)}.#{format_function(from.function)} -> #{format_module(to.module)}.#{format_function(to.function)}"
  end

  def format(%__MODULE__{
        type: :ambiguous_call,
        caller: caller,
        function: function,
        arity: arity,
        candidates: candidates
      }) do
    candidate_list =
      candidates
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> Enum.sort()
      |> Enum.join(", ")

    "ambiguous call in #{format_module(caller.module)}.#{format_function(caller.function)}/#{arity} for #{format_function(function)}/#{arity} (candidates: #{candidate_list})"
  end

  def format(error), do: inspect(error)

  defp format_module(nil), do: "<unknown module>"
  defp format_module(module), do: to_string(module)

  defp format_function(nil), do: "<unknown function>"
  defp format_function(function), do: to_string(function)
end
