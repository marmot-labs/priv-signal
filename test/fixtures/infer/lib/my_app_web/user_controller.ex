defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller

  def create(conn, params) do
    {:ok, conn, params}
  end
end
