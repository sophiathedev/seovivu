defmodule SeovivuWeb.BatchFeaturesTest do
  use SeovivuWeb.ConnCase, async: true

  alias Seovivu.{Billing, Seo}

  describe "rendering the batch tool pages" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, user_fixture())}

    test "Check Index", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/app/check-index")
      assert html =~ "Kiểm tra Index"
    end

    test "URL Status", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/app/url-status")
      assert html =~ "Kiểm tra trạng thái URL"
    end

    test "Backlink (has a target field)", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/app/backlink")
      assert html =~ "Kiểm tra Backlink"
      assert html =~ "Tên miền đích"
    end

    test "Redirect 301", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/app/redirect")
      assert html =~ "Trạng thái Redirect 301"
    end
  end

  describe "starting a Check Index batch" do
    test "reserves credits and shows progress when the user has enough", %{conn: conn} do
      user = user_fixture() |> with_credits(:main, 10)
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/app/check-index")

      html = lv |> form("form", %{"urls" => "a.com\nb.com"}) |> render_submit()

      assert html =~ "Tiến độ"
      assert html =~ "a.com"
      assert Billing.get_wallet(user.id, :main).credits == 8
      assert [job] = Seo.list_jobs(user.id, :check_index)
      assert job.total == 2
    end

    test "flashes an error when credits are insufficient", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/app/check-index")

      html = lv |> form("form", %{"urls" => "a.com\nb.com"}) |> render_submit()

      assert html =~ "Không đủ credit"
      assert Seo.list_jobs(user.id, :check_index) == []
    end
  end
end
