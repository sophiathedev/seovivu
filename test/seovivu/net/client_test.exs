defmodule Seovivu.Net.ClientTest do
  use ExUnit.Case, async: true

  alias Seovivu.Net.Client

  describe "find_backlinks/2" do
    test "lists every anchor pointing at the target host with its rel" do
      body = """
      <html><body>
        <a href="https://vidu.com/trang">Anchor một</a>
        <a href="http://vidu.com" rel="nofollow noopener">Anchor hai</a>
        <a href="https://khac.com">Không tính</a>
      </body></html>
      """

      anchors = Client.find_backlinks(body, "vidu.com")

      assert [
               %{"text" => "Anchor một", "rel" => "dofollow"},
               %{"text" => "Anchor hai", "rel" => "nofollow"}
             ] = anchors
    end

    test "matches regardless of scheme/path in the target" do
      body = ~s(<a href="https://vidu.com/abc">x</a>)
      assert [%{"rel" => "dofollow"}] = Client.find_backlinks(body, "https://vidu.com/xyz")
    end

    test "returns [] when no anchor points to the host" do
      assert [] = Client.find_backlinks(~s(<a href="https://khac.com">x</a>), "vidu.com")
    end

    test "returns [] for an empty target" do
      assert [] = Client.find_backlinks("<a href='vidu.com'>x</a>", "")
    end
  end
end
