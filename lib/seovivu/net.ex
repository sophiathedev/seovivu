defmodule Seovivu.Net do
  @moduledoc """
  Outbound networking: the proxy inventory used by the proxied check tools.

  Live connectivity testing and random rotation (`ProxyPool`) plus the Req-based
  `Client` arrive in Phase 3; this context provides the CRUD the admin
  "API Key & Proxy" page needs now.
  """
  import Ecto.Query, warn: false

  alias Seovivu.Repo
  alias Seovivu.Net.Proxy

  def list_proxies do
    Proxy |> order_by(:id) |> Repo.all()
  end

  @doc "Active proxies eligible for rotation (active and not known-failed)."
  def list_active_proxies do
    Proxy
    |> where([p], p.active == true and p.status != :failed)
    |> order_by(:id)
    |> Repo.all()
  end

  @doc "Marks a proxy as failed (e.g. after a connection error during a request)."
  def mark_failed(proxy_id) when is_integer(proxy_id) do
    {count, _} =
      Proxy
      |> where(id: ^proxy_id)
      |> Repo.update_all(set: [status: :failed, last_tested_at: now()])

    if count > 0, do: Seovivu.Net.ProxyPool.refresh()
    :ok
  end

  def mark_failed(_), do: :ok

  def get_proxy!(id), do: Repo.get!(Proxy, id)

  def change_proxy(%Proxy{} = proxy, attrs \\ %{}), do: Proxy.changeset(proxy, attrs)

  def create_proxy(attrs) do
    %Proxy{} |> Proxy.changeset(attrs) |> Repo.insert()
  end

  def update_proxy(%Proxy{} = proxy, attrs) do
    proxy |> Proxy.changeset(attrs) |> Repo.update()
  end

  def delete_proxy(%Proxy{} = proxy), do: Repo.delete(proxy)

  @test_url "https://api.ipify.org?format=json"

  @doc """
  Probes a proxy with a real HTTP request, records latency + status, and
  persists the result. Returns the updated proxy.
  """
  def test_proxy(%Proxy{} = proxy) do
    attrs =
      case probe_proxy(proxy) do
        {:ok, latency} -> %{status: :ok, last_latency_ms: latency, last_tested_at: now()}
        {:error, _} -> %{status: :failed, last_latency_ms: nil, last_tested_at: now()}
      end

    {:ok, proxy} = proxy |> Proxy.test_result_changeset(attrs) |> Repo.update()
    proxy
  end

  @doc """
  Probes proxy connection details (host/port/credentials) WITHOUT persisting,
  for testing straight from an input form. Returns `{:ok, latency_ms}` or
  `{:error, reason}`. `attrs` accepts string or atom keys.
  """
  def test_proxy_attrs(attrs) do
    changeset = Proxy.changeset(%Proxy{}, attrs)

    if changeset.valid? do
      probe_proxy(Ecto.Changeset.apply_changes(changeset))
    else
      {:error, :invalid}
    end
  end

  # Runs the actual HTTP request through the proxy. No DB writes.
  defp probe_proxy(%Proxy{} = proxy) do
    started = System.monotonic_time(:millisecond)

    # No `finch:` here — `connect_options` (the proxy) makes Req start a
    # dedicated per-proxy pool; passing `:finch` alongside it would raise.
    result =
      Req.get(@test_url,
        connect_options: req_proxy_opts(proxy),
        retry: false,
        receive_timeout: 10_000,
        max_redirects: 0
      )

    case result do
      {:ok, %{status: status}} when status in 200..299 ->
        {:ok, System.monotonic_time(:millisecond) - started}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Tests every proxy concurrently and returns `{ok_count, failed_count}`."
  def test_all_proxies do
    results =
      list_proxies()
      |> Task.async_stream(&test_proxy/1,
        max_concurrency: 10,
        timeout: 15_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, %Proxy{status: status}} -> status
        _ -> :failed
      end)

    {Enum.count(results, &(&1 == :ok)), Enum.count(results, &(&1 != :ok))}
  end

  @doc """
  Verifies a ScrapingDog API key with a minimal real scrape. Returns `:ok` or
  `{:error, reason}`. Note: this consumes one ScrapingDog credit.
  """
  def test_scrapingdog(api_key) when is_binary(api_key) and api_key != "" do
    case Req.get("https://api.scrapingdog.com/google",
           params: [
             api_key: api_key,
             query: "site:example.com",
             country: "vn",
             advance_search: "false",
             domain: "google.com"
           ],
           finch: Seovivu.Finch,
           retry: false,
           receive_timeout: 20_000
         ) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def test_scrapingdog(_), do: {:error, :no_key}

  @doc """
  Builds Req/Mint `connect_options` that route through the given proxy,
  including Basic proxy auth when credentials are present.
  """
  def req_proxy_opts(%Proxy{protocol: protocol, host: host, port: port} = proxy) do
    scheme = if protocol == :https, do: :https, else: :http
    base = [proxy: {scheme, host, port, []}]

    case proxy do
      %Proxy{username: u, password: p} when is_binary(u) and u != "" ->
        auth = "Basic " <> Base.encode64("#{u}:#{p}")
        base ++ [proxy_headers: [{"proxy-authorization", auth}]]

      _ ->
        base
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  @doc """
  Bulk-imports proxies from a newline-separated list in `host:port` or
  `host:port:user:pass` form. Returns `{inserted_count, errors}`.
  """
  def import_proxies(text) when is_binary(text) do
    text
    |> String.split(["\n", "\r\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce({0, []}, fn line, {count, errors} ->
      case parse_proxy_line(line) do
        {:ok, attrs} ->
          case create_proxy(attrs) do
            {:ok, _} -> {count + 1, errors}
            {:error, _} -> {count, [line | errors]}
          end

        :error ->
          {count, [line | errors]}
      end
    end)
  end

  defp parse_proxy_line(line) do
    case String.split(line, ":") do
      [host, port] ->
        build_proxy_attrs(host, port, nil, nil)

      [host, port, user, pass] ->
        build_proxy_attrs(host, port, user, pass)

      _ ->
        :error
    end
  end

  defp build_proxy_attrs(host, port, user, pass) do
    case Integer.parse(port) do
      {port_int, ""} ->
        {:ok, %{host: host, port: port_int, username: user, password: pass, protocol: :http}}

      _ ->
        :error
    end
  end
end
