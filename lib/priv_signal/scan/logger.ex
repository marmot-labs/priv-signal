defmodule PrivSignal.Scan.Logger do
  @moduledoc false

  alias PrivSignal.Scan.Inventory
  alias PrivSignal.Scan.Scanner.Logging

  def scan_file(path, %Inventory{} = inventory) do
    Logging.scan_file(path, inventory)
  end

  def scan_ast(ast, path, %Inventory{} = inventory) do
    Logging.scan_ast(ast, %{path: path}, inventory, [])
  end
end
