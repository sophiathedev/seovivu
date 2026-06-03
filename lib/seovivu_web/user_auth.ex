defmodule SeovivuWeb.UserAuth do
  @moduledoc """
  Session-based authentication: plugs for the router and `on_mount` hooks for
  LiveView `live_session`s. Modeled on `phx.gen.auth` but with no email/remember
  flows — login is by Telegram username/ID + password.
  """
  use SeovivuWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Seovivu.Accounts

  @doc """
  Logs the user in: rotates the session, stores a fresh session token, records
  the login (IP + user agent), and redirects.
  """
  def log_in_user(conn, user, _params \\ %{}) do
    token = Accounts.generate_user_session_token(user)
    Accounts.log_login(user, format_ip(conn), user_agent(conn))
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> renew_session()
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
    |> redirect(to: user_return_to || signed_in_path(user))
  end

  @doc "Logs the user out, dropping their session token and session."
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      SeovivuWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> redirect(to: ~p"/login")
  end

  @doc "Plug: assigns `:current_user` from the session token (or nil)."
  def fetch_current_user(conn, _opts) do
    user =
      with token when is_binary(token) <- get_session(conn, :user_token),
           %Accounts.User{} = user <- Accounts.get_user_by_session_token(token) do
        user
      else
        _ -> nil
      end

    assign(conn, :current_user, user)
  end

  @doc "Plug: requires an authenticated, active user."
  def require_authenticated_user(conn, _opts) do
    case conn.assigns[:current_user] do
      %Accounts.User{status: :active} ->
        conn

      _ ->
        conn
        |> put_flash(:error, "Bạn cần đăng nhập để truy cập trang này.")
        |> maybe_store_return_to()
        |> redirect(to: ~p"/login")
        |> halt()
    end
  end

  @doc """
  Plug: forces a user whose password was system-issued to change it before
  reaching any protected page. Lets the change-password page itself through so
  there is no redirect loop.
  """
  def require_password_changed(conn, _opts) do
    user = conn.assigns[:current_user]

    cond do
      not match?(%Accounts.User{must_change_password: true}, user) -> conn
      conn.request_path == ~p"/change-password" -> conn
      true -> conn |> redirect(to: ~p"/change-password") |> halt()
    end
  end

  @doc "Plug: requires the current user to be an admin."
  def require_admin(conn, _opts) do
    case conn.assigns[:current_user] do
      %Accounts.User{role: :admin} ->
        conn

      _ ->
        conn
        |> put_flash(:error, "Bạn không có quyền truy cập trang này.")
        |> redirect(to: ~p"/app")
        |> halt()
    end
  end

  @doc "Plug: redirects already-authenticated users away from auth pages."
  def redirect_if_user_is_authenticated(conn, _opts) do
    case conn.assigns[:current_user] do
      %Accounts.User{} = user -> conn |> redirect(to: signed_in_path(user)) |> halt()
      _ -> conn
    end
  end

  ## LiveView on_mount hooks

  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    case socket.assigns.current_user do
      %Accounts.User{status: :active} ->
        {:cont, socket}

      _ ->
        socket =
          socket
          |> Phoenix.LiveView.put_flash(:error, "Bạn cần đăng nhập để truy cập trang này.")
          |> Phoenix.LiveView.redirect(to: ~p"/login")

        {:halt, socket}
    end
  end

  def on_mount(:redirect_if_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    case socket.assigns.current_user do
      %Accounts.User{} = user ->
        {:halt, Phoenix.LiveView.redirect(socket, to: signed_in_path(user))}

      _ ->
        {:cont, socket}
    end
  end

  def on_mount(:ensure_admin, params, session, socket) do
    case on_mount(:ensure_authenticated, params, session, socket) do
      {:cont, socket} ->
        if socket.assigns.current_user.role == :admin do
          {:cont, socket}
        else
          {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/app")}
        end

      halted ->
        halted
    end
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      with token when is_binary(token) <- session["user_token"] do
        Accounts.get_user_by_session_token(token)
      else
        _ -> nil
      end
    end)
  end

  ## Helpers

  @doc "Where to send a user after they sign in."
  def signed_in_path(%Accounts.User{must_change_password: true}), do: ~p"/change-password"
  def signed_in_path(%Accounts.User{role: :admin}), do: ~p"/admin"
  def signed_in_path(_user), do: ~p"/app"

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp format_ip(conn) do
    case conn.remote_ip do
      nil -> nil
      ip -> ip |> :inet.ntoa() |> to_string()
    end
  end

  defp user_agent(conn) do
    case get_req_header(conn, "user-agent") do
      [ua | _] -> ua
      _ -> nil
    end
  end
end
