defmodule SeovivuWeb.SessionControllerTest do
  use SeovivuWeb.ConnCase, async: true

  alias Seovivu.Accounts

  test "GET /login renders the login page", %{conn: conn} do
    conn = get(conn, ~p"/login")
    assert html_response(conn, 200) =~ "Đăng nhập"
  end

  test "logs in with valid credentials and records the session", %{conn: conn} do
    user = user_fixture()
    {:ok, _} = Accounts.set_password(user, "supersecret123")

    conn =
      post(conn, ~p"/login", %{
        "user" => %{"identifier" => user.username, "password" => "supersecret123"}
      })

    assert redirected_to(conn) == ~p"/app"
    assert get_session(conn, :user_token)
    assert Accounts.get_user!(user.id).last_login_at
  end

  test "rejects an invalid password", %{conn: conn} do
    user = user_fixture()
    {:ok, _} = Accounts.set_password(user, "supersecret123")

    conn =
      post(conn, ~p"/login", %{
        "user" => %{"identifier" => user.username, "password" => "wrong"}
      })

    assert html_response(conn, 200) =~ "Sai thông tin đăng nhập"
    refute get_session(conn, :user_token)
  end
end
