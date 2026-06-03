defmodule SeovivuWeb.RobotsLiveTest do
  use SeovivuWeb.ConnCase, async: true

  setup %{conn: conn}, do: %{conn: log_in_user(conn, user_fixture())}

  test "renders the robots.txt generator", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/app/robots")
    assert html =~ "Robots.txt"
  end

  test "builds robots.txt from the form fields", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/app/robots")

    html =
      lv
      |> element("form")
      |> render_change(%{
        "user_agent" => "*",
        "disallow" => "/admin\n/secret",
        "allow" => "/public",
        "crawl_delay" => "5",
        "sitemap" => "https://vidu.com/sitemap.xml"
      })

    assert html =~ "User-agent: *"
    assert html =~ "Disallow: /admin"
    assert html =~ "Disallow: /secret"
    assert html =~ "Allow: /public"
    assert html =~ "Crawl-delay: 5"
    assert html =~ "Sitemap: https://vidu.com/sitemap.xml"
  end
end
