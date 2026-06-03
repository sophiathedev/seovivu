defmodule SeovivuWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use SeovivuWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint SeovivuWeb.Endpoint

      use SeovivuWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Seovivu.Fixtures
      import SeovivuWeb.ConnCase
    end
  end

  setup tags do
    Seovivu.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc "Puts a valid session token for `user` on the conn (logs them in)."
  def log_in_user(conn, user) do
    token = Seovivu.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  @doc "Setup helper: builds a logged-in regular user. Returns `%{conn:, user:}`."
  def register_and_log_in_user(%{conn: conn}) do
    user = Seovivu.Fixtures.user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  @doc "Setup helper: builds a logged-in admin. Returns `%{conn:, user:}`."
  def register_and_log_in_admin(%{conn: conn}) do
    user = Seovivu.Fixtures.admin_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end
end
