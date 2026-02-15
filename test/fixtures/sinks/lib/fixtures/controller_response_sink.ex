defmodule Fixtures.UserController do
  import Plug.Conn
  import Phoenix.Controller

  def show(conn, user) do
    json(conn, %{email: user.email, phone: user.phone})
  end
end
