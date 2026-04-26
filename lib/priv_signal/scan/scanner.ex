defmodule PrivSignal.Scan.Scanner do
  @moduledoc """
  Provides shared validation for scanner modules used by the scan runner.
  """

  @callback scan_ast(Macro.t(), map(), struct(), keyword()) :: [map()]

  def valid_module?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :scan_ast, 4)
  end

  def valid_module?(_), do: false
end
