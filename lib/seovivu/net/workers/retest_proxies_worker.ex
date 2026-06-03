defmodule Seovivu.Net.Workers.RetestProxiesWorker do
  @moduledoc """
  Periodically re-tests every proxy (scheduled via Oban Cron) so proxies that
  recovered get flipped back to `:ok` and dead ones to `:failed`, keeping the
  rotation pool healthy. Refreshes `ProxyPool` afterwards.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Seovivu.Net
  alias Seovivu.Net.ProxyPool

  @impl Oban.Worker
  def perform(_job) do
    {ok, failed} = Net.test_all_proxies()
    ProxyPool.refresh()
    {:ok, %{ok: ok, failed: failed}}
  end
end
