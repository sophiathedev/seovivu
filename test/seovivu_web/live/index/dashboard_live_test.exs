defmodule SeovivuWeb.Index.DashboardLiveTest do
  use SeovivuWeb.ConnCase, async: true

  alias Seovivu.{Billing, Indexer}

  # The Submit-Index app lives on the index. subdomain host.
  defp index_conn(conn, user), do: %{log_in_user(conn, user) | host: "index.localhost"}

  test "renders the Submit-Index dashboard", %{conn: conn} do
    user = user_fixture() |> with_credits(:index, 10)
    {:ok, _lv, html} = live(index_conn(conn, user), "/")
    assert html =~ "Dự án Gửi Index"
  end

  test "creates a project, charging the index wallet", %{conn: conn} do
    user = user_fixture() |> with_credits(:index, 10)
    {:ok, lv, _html} = live(index_conn(conn, user), "/")

    html =
      lv
      |> form("form", %{"name" => "Dự án thử", "urls" => "a.com\nb.com\nc.com"})
      |> render_submit()

    assert html =~ "Dự án thử"
    assert Billing.get_wallet(user.id, :index).credits == 7
    assert [project] = Indexer.list_projects(user.id)
    assert project.url_count == 3
  end

  test "rejects creation without enough index credits", %{conn: conn} do
    user = user_fixture() |> with_credits(:index, 1)
    {:ok, lv, _html} = live(index_conn(conn, user), "/")

    html =
      lv |> form("form", %{"name" => "X", "urls" => "a.com\nb.com\nc.com"}) |> render_submit()

    assert html =~ "Không đủ credit Index"
    assert Indexer.list_projects(user.id) == []
  end
end
