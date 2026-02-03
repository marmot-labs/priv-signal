defmodule PrivSignal.Git.Options do
  @moduledoc false

  @default_base "origin/main"
  @default_head "HEAD"

  def parse(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        switches: [base: :string, head: :string],
        aliases: [b: :base, h: :head]
      )

    %{
      base: Keyword.get(opts, :base, @default_base),
      head: Keyword.get(opts, :head, @default_head)
    }
  end
end
