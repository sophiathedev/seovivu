defmodule SeovivuWeb.Index.SsoController do
  @moduledoc """
  Subdomain endpoint that completes the SSO hand-off from the main host: verifies
  the short-lived token and logs the user into THIS host's own session (so no
  shared cookie domain is needed). Tokens are valid for 60 seconds and single
  purpose ("index_sso").
  """
  use SeovivuWeb, :controller

  alias Seovivu.Accounts
  alias SeovivuWeb.UserAuth

  def create(conn, %{"token" => token}) do
    case Phoenix.Token.verify(SeovivuWeb.Endpoint, "index_sso", token, max_age: 60) do
      {:ok, user_id} ->
        case Accounts.get_user(user_id) do
          %Accounts.User{status: :active} = user ->
            # Redirect to the subdomain root after logging in (not /app).
            conn
            |> put_session(:user_return_to, "/")
            |> UserAuth.log_in_user(user)

          _ ->
            bounce(conn)
        end

      _ ->
        bounce(conn)
    end
  end

  def create(conn, _params), do: bounce(conn)

  # On any failure, send the user back to the main host to (re)authenticate.
  defp bounce(conn) do
    redirect(conn, external: SeovivuWeb.Endpoint.url())
  end
end
