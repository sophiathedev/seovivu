defmodule SeovivuWeb.SessionController do
  use SeovivuWeb, :controller

  alias Seovivu.{Accounts, RateLimiter, Telegram}
  alias SeovivuWeb.UserAuth

  # Forgot-password throttle: per account and per client IP.
  @forgot_id_limit 1
  @forgot_id_window :timer.seconds(120)
  @forgot_ip_limit 15
  @forgot_ip_window :timer.minutes(10)

  def new(conn, _params) do
    render(conn, :new, page_title: "Đăng nhập")
  end

  @doc """
  Forgot-password: triggers the Telegram bot's `/reset` flow for the account
  matching the identifier, so the bot DMs a fresh password. Always shows the
  same generic message (no account enumeration).
  """
  def forgot(conn, %{"user" => %{"identifier" => identifier}})
      when is_binary(identifier) and identifier != "" do
    if within_rate_limit?(identifier, client_ip(conn)) do
      identifier
      |> Accounts.get_user_by_identifier()
      |> Telegram.request_reset()

      conn
      |> put_flash(
        :info,
        "Nếu tài khoản tồn tại và đã liên kết Telegram, mật khẩu mới đã được gửi qua bot. Hãy kiểm tra Telegram của bạn."
      )
      |> redirect(to: ~p"/login")
    else
      conn
      |> put_flash(
        :error,
        "Bạn đã yêu cầu đặt lại mật khẩu gần đây. Vui lòng kiểm tra Telegram hoặc thử lại sau vài phút."
      )
      |> redirect(to: ~p"/login")
    end
  end

  def forgot(conn, _params) do
    conn
    |> put_flash(:error, "Vui lòng nhập tên Telegram hoặc ID để đặt lại mật khẩu.")
    |> redirect(to: ~p"/login")
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

  # Throttles password-reset requests by both account identifier and client IP.
  defp within_rate_limit?(identifier, ip) do
    id_key = {:forgot_id, identifier |> String.trim() |> String.downcase()}
    ip_key = {:forgot_ip, ip}

    RateLimiter.hit(ip_key, @forgot_ip_limit, @forgot_ip_window) == :ok and
      RateLimiter.hit(id_key, @forgot_id_limit, @forgot_id_window) == :ok
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
