defmodule SeovivuWeb.Admin.AdminLiveTest do
  use SeovivuWeb.ConnCase, async: true

  alias Seovivu.{Billing, Catalog, Indexer}

  describe "access control" do
    test "a regular user is redirected away from /admin", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      assert {:error, {kind, %{to: "/app"}}} = live(conn, ~p"/admin")
      assert kind in [:redirect, :live_redirect]
    end
  end

  describe "as admin" do
    setup :register_and_log_in_admin

    test "overview renders the stat cards and charts", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/admin")
      assert html =~ "Tổng quan"
      assert html =~ "Lượt chạy theo công cụ"
      assert html =~ "Dự án Gửi Index theo trạng thái"
    end

    test "quota: creating a package shows it in the table", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/admin/quota")
      # The form lives in a slide-over panel opened via "Tạo gói mới".
      refute html =~ "phx-submit=\"save\""

      assert lv |> render_click("new") =~ "Tạo gói mới"

      html =
        lv
        |> form("form", %{
          "package" => %{"name" => "Gói Vàng", "credits" => "1000", "days" => "30"}
        })
        |> render_submit()

      assert html =~ "Gói Vàng"
      assert [%{name: "Gói Vàng"}] = Catalog.list_packages(:main)
    end

    test "quota: status toggle flips active in place", %{conn: conn} do
      {:ok, pkg} = Catalog.create_package(%{name: "Gói X", credits: 100, days: 7, kind: :main})
      assert pkg.active

      {:ok, lv, _html} = live(conn, ~p"/admin/quota")
      lv |> render_click("toggle_active", %{"id" => to_string(pkg.id)})

      refute Catalog.get_package!(pkg.id).active

      lv |> render_click("toggle_active", %{"id" => to_string(pkg.id)})
      assert Catalog.get_package!(pkg.id).active
    end

    test "user manager: open the manage panel and adjust credits", %{conn: conn} do
      target = user_fixture()
      {:ok, lv, html} = live(conn, ~p"/admin/users")
      assert html =~ target.username

      assert lv |> render_click("manage", %{"id" => to_string(target.id)}) =~ "Điều chỉnh credit"

      lv
      |> element("form[phx-submit=adjust_credit]")
      |> render_submit(%{"amount" => "250", "op" => "add"})

      assert Billing.get_wallet(target.id, :main).credits == 250
    end

    test "user manager: numbered pagination jumps to a chosen page", %{conn: conn} do
      # 25 fixtures + the admin from setup = 26 users -> 2 pages (@per_page 20).
      for _ <- 1..25, do: user_fixture()

      {:ok, lv, html} = live(conn, ~p"/admin/users")
      assert html =~ "Hiển thị 1-20 / 26"
      # A jump-to-page-2 button exists (not just prev/next).
      assert html =~ ~s(phx-value-page="2")

      html2 = lv |> render_click("page", %{"page" => "2"})
      assert html2 =~ "Hiển thị 21-26 / 26"
    end

    test "user manager: alert offers to issue passwords to imported accounts", %{conn: conn} do
      _imported = user_fixture()

      {:ok, lv, html} = live(conn, ~p"/admin/users")
      assert html =~ "tài khoản chưa có mật khẩu"

      # Telegram isn't configured in tests, so issuing reports the config error
      # rather than provisioning passwords.
      assert lv |> render_click("issue_passwords") =~ "Chưa cấu hình bot Telegram"
    end

    test "index projects: list and advance status", %{conn: conn} do
      owner = user_fixture() |> with_credits(:index, 10)
      {:ok, project} = Indexer.create_project(owner, "Dự án QA", "a.com\nb.com")

      {:ok, lv, html} = live(conn, ~p"/admin/index/projects")
      assert html =~ "Dự án QA"

      lv
      |> element("form[phx-change=set_status]")
      |> render_change(%{"_id" => to_string(project.id), "status" => "done"})

      assert Indexer.get_project!(project.id).status == :done
    end
  end
end
