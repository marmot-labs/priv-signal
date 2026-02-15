defmodule Fixtures.HttpClientSink do
  def send_user(user) do
    Req.post!("https://api.segment.io/v1/track", json: %{email: user.email})
  end
end
