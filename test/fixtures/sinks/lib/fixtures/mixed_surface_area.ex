defmodule Fixtures.MixedSurfaceArea do
  def perform(repo, user, socket) do
    _ = repo.get(MyApp.Accounts.User, user.id)
    :telemetry.execute([:mixed, :event], %{count: 1}, %{email: user.email})
    _ = Req.post!("https://api.stripe.com/v1/customers", form: %{email: user.email})
    {:ok, assign(socket, :email, user.email)}
  end
end
