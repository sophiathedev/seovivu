defmodule SeovivuWeb.PasswordController do
  @moduledoc """
  Forced password change. When a user logs in with a system-issued password
  (the one the Telegram bot sent them), `require_password_changed` routes them
  here until they set a password of their own.
  """
  use SeovivuWeb, :controller

  alias Seovivu.Accounts
  alias SeovivuWeb.UserAuth

  def edit(conn, _params) do
    render(conn, :edit, page_title: "Đổi mật khẩu")
  end

  def update(conn, %{"user" => params}) do
    user = conn.assigns.current_user
    current = Map.get(params, "current_password", "")
    new = Map.get(params, "password", "")
    confirm = Map.get(params, "password_confirmation", "")

    cond do
      not Accounts.valid_password?(user, current) ->
        fail(conn, "Mật khẩu hiện tại không đúng.")

      String.length(new) < 8 ->
        fail(conn, "Mật khẩu mới phải có ít nhất 8 ký tự.")

      new != confirm ->
        fail(conn, "Mật khẩu nhập lại không khớp.")

      true ->
        case Accounts.set_password(user, new) do
          {:ok, user} ->
            conn
            |> put_flash(:info, "Đã đổi mật khẩu. Lần sau hãy đăng nhập bằng mật khẩu mới.")
            |> redirect(to: UserAuth.signed_in_path(user))

          {:error, _changeset} ->
            fail(conn, "Không đổi được mật khẩu, vui lòng thử lại.")
        end
    end
  end

  defp fail(conn, message) do
    conn
    |> put_flash(:error, message)
    |> render(:edit, page_title: "Đổi mật khẩu")
  end
end
