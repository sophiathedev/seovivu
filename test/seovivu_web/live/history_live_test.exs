defmodule SeovivuWeb.HistoryLiveTest do
  use SeovivuWeb.ConnCase, async: true

  alias Seovivu.Seo

  setup :register_and_log_in_user

  test "renders an empty history", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/app/history")
    assert html =~ "Lịch sử hoạt động"
    assert html =~ "Chưa có lượt chạy nào."
  end

  test "shows usage totals and recent jobs", %{conn: conn, user: user} do
    with_credits(user, :main, 10)
    {:ok, job} = Seo.start_batch(user, :check_index, "a.com\nb.com")
    [i1, i2] = Seo.list_items(job.id)
    Seo.record_item(i1, :success, %{result: %{}})
    Seo.record_item(i2, :failed, %{result: %{}})
    Seo.finalize_job(Seo.get_job!(job.id))

    {:ok, _lv, html} = live(conn, ~p"/app/history")
    assert html =~ "Lịch sử hoạt động"
    assert html =~ "Kiểm tra Index"
  end
end
