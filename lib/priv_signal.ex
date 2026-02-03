defmodule PrivSignal do
  @moduledoc """
  Core helpers for the PrivSignal CLI.
  """

  @config_file "priv-signal.yml"

  @doc """
  Returns the default config file name.
  """
  def config_path do
    @config_file
  end
end
