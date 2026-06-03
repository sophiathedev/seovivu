defmodule SeovivuWeb.IndexHandoffController do
  @moduledoc """
  Main-host endpoint that hands an authenticated user off to the index.seovivu.com
  subdomain WITHOUT a shared session cookie: it signs a short-lived token bound to
  the current user and redirects to the subdomain's `/sso` endpoint, which
  exchanges it for that host's own session.
  """
  use SeovivuWeb, :controller

  @doc "Signs an SSO token for the current user and redirects to the index subdomain."
  def create(conn, _params) do
    token =
      Phoenix.Token.sign(SeovivuWeb.Endpoint, "index_sso", conn.assigns.current_user.id)

    redirect(conn,
      external: SeovivuWeb.IndexHandoffController.index_url() <> "/sso?token=#{token}"
    )
  end

  @doc "Absolute URL of the index subdomain (index.<host>)."
  def index_url do
    uri = URI.parse(SeovivuWeb.Endpoint.url())
    URI.to_string(%{uri | host: "index." <> (uri.host || "")})
  end
end
