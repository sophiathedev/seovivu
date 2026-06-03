defmodule SeovivuWeb.TimeTest do
  use ExUnit.Case, async: true

  alias SeovivuWeb.Time

  test "renders a UTC datetime in Asia/Ho_Chi_Minh (+7)" do
    dt = ~U[2026-06-02 00:30:00Z]
    assert Time.datetime(dt) == "02/06/2026 07:30"
    assert Time.date(dt) == "02/06/2026"
  end

  test "rolls over the date when +7 crosses midnight" do
    # 19:30 UTC -> 02:30 next day local
    assert Time.date(~U[2026-06-02 19:30:00Z]) == "03/06/2026"
  end

  test "returns a dash for nil" do
    assert Time.datetime(nil) == "-"
  end
end
