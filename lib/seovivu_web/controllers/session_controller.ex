defmodule SeovivuWeb.SessionController do
  use SeovivuWeb, :controller

  alias Seovivu.Accounts
  alias SeovivuWeb.UserAuth

  def new(conn, _params) do
    render(conn, :new, page_title: "Đăng nhập")
  end

  def create(conn, %{"user" => user_params}) do
    %{"identifier" => identifier, "password" => password} = user_params

    case Accounts.get_user_by_telegram_and_password(identifier, password) do
      nil ->
        conn
        |> put_flash(:error, "Sai thông tin đăng nhập, hoặc tài khoản đã bị khóa.")
        |> render(:new, page_title: "Đăng nhập")

      user ->
        Accounts.log_login(user, client_ip(conn), user_agent(conn))

        conn
        |> put_flash(:info, "Chào mừng trở lại!")
        |> UserAuth.log_in_user(user, user_params)
    end
  end

  # Prefer the forwarded client IP (we run behind a tunnel/proxy in prod).
  defp client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] ->
        forwarded |> String.split(",") |> List.first() |> String.trim()

      _ ->
        conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  defp user_agent(conn), do: conn |> get_req_header("user-agent") |> List.first()

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Bạn đã đăng xuất.")
    |> UserAuth.log_out_user()
  end
end
