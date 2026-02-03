defmodule PrivSignal.Output.JSON do
  @moduledoc false

  def render(%{category: category, reasons: reasons, events: events}) do
    %{
      risk_category: category,
      reasons: reasons,
      events: events
    }
  end
end
