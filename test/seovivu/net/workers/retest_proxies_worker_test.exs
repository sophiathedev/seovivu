defmodule Seovivu.Net.Workers.RetestProxiesWorkerTest do
  # async: false so the shared sandbox connection is visible to ProxyPool (which
  # the worker refreshes) — avoids an ownership error in that process.
  use Seovivu.DataCase, async: false
  use Oban.Testing, repo: Seovivu.Repo

  alias Seovivu.Net.Workers.RetestProxiesWorker

  test "succeeds and reports zero counts when no proxies are configured" do
    assert {:ok, %{ok: 0, failed: 0}} = perform_job(RetestProxiesWorker, %{})
  end
end
