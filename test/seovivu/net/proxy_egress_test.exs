defmodule Seovivu.Net.ProxyEgressTest do
  @moduledoc """
  Security guarantee: the proxied check tools (URL Status, Backlink, 301
  Redirect) must NEVER egress from the VPS origin IP. They route through a random
  proxy, and when no proxy is configured they hard-fail with `:no_proxy` rather
  than silently falling back to a direct request that would leak the origin IP.

  (Check Index is intentionally direct — it uses the ScrapingDog API, which has
  its own rotating IPs — so it is not covered here.)
  """
  use ExUnit.Case, async: false

  alias Seovivu.Net
  alias Seovivu.Net.{Client, Proxy, ProxyPool}

  @pool_table ProxyPool

  setup do
    # Snapshot and restore the in-memory pool so we don't disturb other tests.
    previous =
      case :ets.lookup(@pool_table, :proxies) do
        [{:proxies, list}] -> list
        _ -> []
      end

    on_exit(fn -> :ets.insert(@pool_table, {:proxies, previous}) end)
    :ok
  end

  describe "no proxy available" do
    setup do
      :ets.insert(@pool_table, {:proxies, []})
      assert ProxyPool.random() == :none
      :ok
    end

    test "url_status hard-fails instead of going direct" do
      assert {:error, :no_proxy} = Client.url_status("https://example.com")
    end

    test "fetch_body (backlink) hard-fails instead of going direct" do
      assert {:error, :no_proxy} = Client.fetch_body("https://example.com")
    end

    test "redirect_status hard-fails instead of going direct" do
      assert {:error, :no_proxy} = Client.redirect_status("https://example.com")
    end
  end

  describe "proxy injection" do
    test "req_proxy_opts routes through the proxy (origin IP never used)" do
      proxy = %Proxy{protocol: :http, host: "10.0.0.9", port: 8080}
      opts = Net.req_proxy_opts(proxy)

      assert opts[:proxy] == {:http, "10.0.0.9", 8080, []}
    end

    test "req_proxy_opts carries Basic proxy auth when credentials are set" do
      proxy = %Proxy{
        protocol: :https,
        host: "p.example",
        port: 3128,
        username: "u",
        password: "pw"
      }

      opts = Net.req_proxy_opts(proxy)

      assert opts[:proxy] == {:https, "p.example", 3128, []}
      assert [{"proxy-authorization", "Basic " <> encoded}] = opts[:proxy_headers]
      assert Base.decode64!(encoded) == "u:pw"
    end

    test "ProxyPool.random returns a configured proxy" do
      proxy = %Proxy{id: 1, protocol: :http, host: "1.2.3.4", port: 8000}
      :ets.insert(@pool_table, {:proxies, [proxy]})

      assert {:ok, %Proxy{host: "1.2.3.4"}} = ProxyPool.random()
    end
  end
end
