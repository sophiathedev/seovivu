defmodule SeovivuWeb.Index.SsoControllerTest do
  use SeovivuWeb.ConnCase, async: true

  alias Seovivu.Accounts.User
  alias Seovivu.Repo

  defp active_user do
    {:ok, user} =
      %User{}
      |> User.telegram_changeset(%{
        telegram_id: System.unique_integer([:positive]),
        telegram_username: "u",
        telegram_first_name: "U",
        username: "u#{System.unique_integer([:positive])}",
        role: :user
      })
      |> Repo.insert()

    user
  end

  defp token_for(user_id),
    do: Phoenix.Token.sign(SeovivuWeb.Endpoint, "index_sso", user_id)

  test "a valid token logs the user into the subdomain session and redirects to /", %{conn: conn} do
    user = active_user()

    conn =
      %{conn | host: "index.localhost"}
      |> get("/sso?token=#{token_for(user.id)}")

    assert redirected_to(conn) == "/"
    assert get_session(conn, :user_token)
  end

  test "an invalid token bounces back to the main host", %{conn: conn} do
    conn =
      %{conn | host: "index.localhost"}
      |> get("/sso?token=not-a-real-token")

    assert redirected_to(conn) =~ ~r{^https?://}
    refute get_session(conn, :user_token)
  end
end
