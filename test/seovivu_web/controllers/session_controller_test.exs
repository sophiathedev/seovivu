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

  describe "POST /forgot-password" do
    test "triggers the bot reset for a known identifier", %{conn: conn} do
      user = user_fixture()
      {:ok, _} = Accounts.set_password(user, "old-password-123")

      conn = post(conn, ~p"/forgot-password", %{"user" => %{"identifier" => user.username}})

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "mật khẩu mới đã được gửi"
      # The password was rotated, so the old one no longer works.
      refute Accounts.valid_password?(Accounts.get_user!(user.id), "old-password-123")
    end

    test "shows the same generic message for an unknown identifier", %{conn: conn} do
      conn = post(conn, ~p"/forgot-password", %{"user" => %{"identifier" => "khong-ton-tai"}})

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "mật khẩu mới đã được gửi"
    end

    test "asks for an identifier when none is given", %{conn: conn} do
      conn = post(conn, ~p"/forgot-password", %{"user" => %{"identifier" => ""}})

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Vui lòng nhập"
    end

    test "throttles a second request for the same identifier", %{conn: conn} do
      user = user_fixture()

      first = post(conn, ~p"/forgot-password", %{"user" => %{"identifier" => user.username}})
      assert Phoenix.Flash.get(first.assigns.flash, :info)

      second = post(conn, ~p"/forgot-password", %{"user" => %{"identifier" => user.username}})
      assert redirected_to(second) == ~p"/login"
      assert Phoenix.Flash.get(second.assigns.flash, :error) =~ "thử lại sau"
    end
  end
end
