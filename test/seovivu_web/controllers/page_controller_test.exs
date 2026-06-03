defmodule SeovivuWeb.PageControllerTest do
  use SeovivuWeb.ConnCase

  test "GET / redirects anonymous visitors to the login page", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/login"
  end
end
