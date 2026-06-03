defmodule SeovivuWeb.DisavowLiveTest do
  use SeovivuWeb.ConnCase, async: true

  setup %{conn: conn}, do: %{conn: log_in_user(conn, user_fixture())}

  test "renders the disavow generator", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/app/disavow")
    assert html =~ "Disavow Link"
  end

  test "generates domain-prefixed lines (dedup + scheme stripped)", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/app/disavow")

    html =
      lv
      |> element("form")
      |> render_change(%{
        "input" => "spam.com\nhttps://bad.net/x\nspam.com",
        "as_domain" => "true"
      })

    assert html =~ "domain:spam.com"
    assert html =~ "domain:bad.net"
  end

  test "raw mode keeps the lines as-is", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/app/disavow")

    html =
      lv
      |> element("form")
      |> render_change(%{"input" => "https://bad.net/x", "as_domain" => "false"})

    assert html =~ "https://bad.net/x"
    refute html =~ "domain:bad.net"
  end
end
