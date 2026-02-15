defmodule Fixtures.DatabaseAccess do
  def load_user(repo, id), do: repo.get(MyApp.Accounts.User, id)
  def save_user(repo, attrs), do: repo.insert(attrs)
end
