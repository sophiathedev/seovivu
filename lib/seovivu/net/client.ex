defmodule Seovivu.Net.Client do
  @moduledoc """
  The single outbound HTTP surface for the feature engines. Two egress modes:

    * **Direct** — Check Index goes straight to the ScrapingDog API (its own
      rotating IPs sit behind the API; no proxy needed).
    * **Proxied** — URL Status / Backlink / 301 Redirect route through a random
      active proxy from `Seovivu.Net.ProxyPool` so the VPS origin IP is never
      exposed. If no proxy is available the request fails (it must NOT silently
      fall back to direct).
  """
  require Logger

  alias Seovivu.{Net, Settings}
  alias Seovivu.Net.ProxyPool

  # ScrapingDog's dedicated Google Search API (returns structured JSON).
  @google_search_url "https://api.scrapingdog.com/google"

  ## Check Index (direct, via ScrapingDog Google Search API) ----------------

  @doc """
  Checks whether `url` is indexed by Google via ScrapingDog's Google Search API
  with a `site:` query. Returns `{:ok, %{indexed: bool, http_status: integer}}`
  or `{:error, reason}`.

  Indexed = the SERP JSON has at least one `organic_results` entry.
  """
  def check_index(url) do
    case Settings.get_value("scrapingdog.api_key") do
      key when is_binary(key) and key != "" ->
        params = [
          api_key: key,
          query: "site:" <> strip_scheme(url),
          country: "vn",
          advance_search: "false",
          domain: "google.com"
        ]

        case Req.get(@google_search_url,
               params: params,
               finch: Seovivu.Finch,
               retry: false,
               receive_timeout: 30_000
             ) do
          {:ok, %Req.Response{status: 200, body: body}} ->
            {:ok, %{indexed: indexed?(body), http_status: 200}}

          {:ok, %Req.Response{status: status}} ->
            {:error, {:http, status}}

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, :no_api_key}
    end
  end

  # Indexed when there is at least one organic result. Req auto-decodes JSON to a
  # map; fall back to decoding a binary body just in case.
  defp indexed?(body) when is_map(body) do
    case Map.get(body, "organic_results") do
      [_ | _] -> true
      _ -> false
    end
  end

  defp indexed?(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> indexed?(decoded)
      _ -> false
    end
  end

  defp indexed?(_), do: false

  ## Proxied requests -------------------------------------------------------

  @doc """
  Performs a GET for `url` through a random proxy. `req_opts` are merged into the
  Req call (e.g. `redirect: false`). Returns `{:ok, %Req.Response{}, proxy,
  latency_ms}`, `{:error, :no_proxy}` when the pool is empty, or
  `{:error, reason, proxy_id}` on a transport error (the proxy is marked failed).
  """
  def request_proxied(url, req_opts \\ []) do
    case ProxyPool.random() do
      {:ok, proxy} ->
        started = System.monotonic_time(:millisecond)

        # NOTE: do NOT pass `finch:` here. When `connect_options` (the proxy) is
        # set, Req raises if `:finch` is also given, and more importantly it
        # auto-starts a dedicated Finch pool keyed by THIS proxy's options — so
        # each proxy gets its own pool, rotation is real, and a connection opened
        # through one proxy is never reused for another. The VPS origin IP is
        # never used because a proxy is ALWAYS set (and `:no_proxy` hard-fails
        # above — there is no direct fallback).
        opts =
          Keyword.merge(
            [
              connect_options: Net.req_proxy_opts(proxy),
              retry: false,
              receive_timeout: 15_000
            ],
            req_opts
          )

        case Req.get(url, opts) do
          {:ok, %Req.Response{} = resp} ->
            {:ok, resp, proxy, System.monotonic_time(:millisecond) - started}

          {:error, reason} ->
            Net.mark_failed(proxy.id)
            {:error, reason, proxy.id}
        end

      :none ->
        {:error, :no_proxy}
    end
  end

  @doc """
  Fetches `url` (following redirects) through a proxy and reports the HTTP
  status. Returns `{:ok, %{http_status, ok, latency_ms, proxy_id}}`,
  `{:error, :no_proxy}`, or `{:error, reason, proxy_id}`.
  """
  def url_status(url) do
    case request_proxied(url, redirect: true, max_redirects: 5) do
      {:ok, %Req.Response{status: status}, proxy, latency} ->
        {:ok,
         %{http_status: status, ok: status in 200..399, latency_ms: latency, proxy_id: proxy.id}}

      other ->
        other
    end
  end

  @doc """
  Fetches `url`'s raw body through a proxy (for backlink analysis). Returns
  `{:ok, %{body, http_status, latency_ms, proxy_id}}` or the proxied-error tuples.
  """
  def fetch_body(url) do
    case request_proxied(url, redirect: true, max_redirects: 5) do
      {:ok, %Req.Response{status: status, body: body}, proxy, latency} ->
        {:ok,
         %{body: to_string(body), http_status: status, latency_ms: latency, proxy_id: proxy.id}}

      other ->
        other
    end
  end

  @doc """
  Reports the immediate redirect of `url` WITHOUT following it. Returns
  `{:ok, %{http_status, location, redirect, latency_ms, proxy_id}}` where
  `location` is the `Location` header (or nil) and `redirect` is true for a 3xx.
  """
  def redirect_status(url) do
    case request_proxied(url, redirect: false, max_redirects: 0) do
      {:ok, %Req.Response{status: status} = resp, proxy, latency} ->
        {:ok,
         %{
           http_status: status,
           location: location_header(resp),
           redirect: status in 300..399,
           latency_ms: latency,
           proxy_id: proxy.id
         }}

      other ->
        other
    end
  end

  defp location_header(%Req.Response{} = resp) do
    case Req.Response.get_header(resp, "location") do
      [loc | _] -> loc
      _ -> nil
    end
  end

  ## Backlink analysis ------------------------------------------------------

  @doc """
  Parses `body` (HTML) and returns every anchor whose `href` points at `target`'s
  host as `[%{"text" => anchor_text, "rel" => "dofollow" | "nofollow"}, ...]`
  (empty list when none / unparseable). Uses Floki for reliable parsing.
  """
  def find_backlinks(body, target) when is_binary(body) and is_binary(target) do
    host = host_of(target)

    with true <- host != "",
         {:ok, document} <- Floki.parse_document(body) do
      document
      |> Floki.find("a[href]")
      |> Enum.filter(fn {"a", attrs, _children} ->
        href = attr(attrs, "href")
        is_binary(href) and String.contains?(href, host)
      end)
      |> Enum.map(fn {"a", attrs, children} ->
        %{"text" => children |> Floki.text() |> String.trim(), "rel" => rel_of(attrs)}
      end)
    else
      _ -> []
    end
  end

  def find_backlinks(_body, _target), do: []

  defp attr(attrs, name) do
    case List.keyfind(attrs, name, 0) do
      {^name, value} -> value
      _ -> nil
    end
  end

  defp rel_of(attrs) do
    rel = attr(attrs, "rel") || ""
    if String.contains?(String.downcase(rel), "nofollow"), do: "nofollow", else: "dofollow"
  end

  # Drops the scheme + trailing slash but KEEPS the path (for the `site:` query).
  defp strip_scheme(url) do
    url
    |> to_string()
    |> String.trim()
    |> String.replace(~r{^https?://}i, "")
    |> String.trim_trailing("/")
  end

  # Just the host (scheme + path removed) — for matching backlink anchors.
  defp host_of(url) do
    url |> strip_scheme() |> String.replace(~r{/.*$}, "")
  end
end
