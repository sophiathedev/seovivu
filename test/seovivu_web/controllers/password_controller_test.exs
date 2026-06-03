defmodule SeovivuWeb.PasswordControllerTest do
  use SeovivuWeb.ConnCase, async: true

  alias Seovivu.{Accounts, Repo}

  # A user who logged in with a system-issued password and must change it.
  defp must_change_user do
    user = user_fixture()
    {:ok, user} = Accounts.set_password(user, "telegram-pass")
    user |> Ecto.Changeset.change(must_change_password: true) |> Repo.update!()
  end

  test "a flagged user is redirected from a protected page to /change-password", %{conn: conn} do
    conn = conn |> log_in_user(must_change_user()) |> get(~p"/app")
    assert redirected_to(conn) == ~p"/change-password"
  end

  test "GET /change-password renders the form", %{conn: conn} do
    conn = conn |> log_in_user(must_change_user()) |> get(~p"/change-password")
    assert html_response(conn, 200) =~ "Đổi mật khẩu"
  end

  test "wrong current password keeps the flag and shows an error", %{conn: conn} do
    user = must_change_user()

    conn =
      conn
      |> log_in_user(user)
      |> put(~p"/change-password", %{
        "user" => %{
          "current_password" => "nope",
          "password" => "brand-new-1",
          "password_confirmation" => "brand-new-1"
        }
      })

    assert html_response(conn, 200) =~ "Mật khẩu hiện tại không đúng"
    assert Accounts.get_user!(user.id).must_change_password
  end

  test "mismatched confirmation is rejected", %{conn: conn} do
    user = must_change_user()

    conn =
      conn
      |> log_in_user(user)
      |> put(~p"/change-password", %{
        "user" => %{
          "current_password" => "telegram-pass",
          "password" => "brand-new-1",
          "password_confirmation" => "different-1"
        }
      })

    assert html_response(conn, 200) =~ "không khớp"
    assert Accounts.get_user!(user.id).must_change_password
  end

  test "valid change clears the flag and redirects into the app", %{conn: conn} do
    user = must_change_user()

    conn =
      conn
      |> log_in_user(user)
      |> put(~p"/change-password", %{
        "user" => %{
          "current_password" => "telegram-pass",
          "password" => "brand-new-1",
          "password_confirmation" => "brand-new-1"
        }
      })

    assert redirected_to(conn) == ~p"/app"
    refute Accounts.get_user!(user.id).must_change_password
    assert Accounts.get_user_by_telegram_and_password(user.username, "brand-new-1")
  end
end
