defmodule SeovivuWeb.PageController do
  use SeovivuWeb, :controller

  # The root path sends visitors into the app: admins to the admin area,
  # signed-in users to their dashboard, and everyone else to the login page.
  def home(conn, _params) do
    case conn.assigns[:current_user] do
      %{role: :admin} -> redirect(conn, to: ~p"/admin")
      %{} -> redirect(conn, to: ~p"/app")
      _ -> redirect(conn, to: ~p"/login")
    end
  end
end
