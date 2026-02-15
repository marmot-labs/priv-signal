defmodule Fixtures.UserLive do
  use Phoenix.LiveView

  def handle_event("save", %{"email" => email}, socket) do
    {:noreply, assign(socket, :email, email)}
  end
end
