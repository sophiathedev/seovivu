defmodule Seovivu.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        SeovivuWeb.Telemetry,
        Seovivu.Repo,
        {DNSCluster, query: Application.get_env(:seovivu, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Seovivu.PubSub},
        # In-memory rate limiter (throttles abuse-prone endpoints, e.g. password reset).
        Seovivu.RateLimiter,
        # Dedicated HTTP connection pool for all outbound requests (feature
        # engines + Telegram). A generous pool keeps concurrent batches from
        # queueing behind one another at the transport layer.
        {Finch,
         name: Seovivu.Finch,
         pools: %{
           default: [size: 64, count: 4]
         }},
        # Cached, rotating pool of active proxies for the proxied check tools.
        Seovivu.Net.ProxyPool,
        # Supervises the per-batch runner tasks for the SEO feature engine.
        {Task.Supervisor, name: Seovivu.Seo.TaskSupervisor},
        # Start the Oban background job supervisor
        {Oban, Application.fetch_env!(:seovivu, Oban)},
        # Start to serve requests, typically the last entry
        SeovivuWeb.Endpoint
      ] ++ recovery_children() ++ telegram_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Seovivu.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # SEO batches run as in-memory tasks; on boot, clean up any job left running
  # by a previous lifetime (refund unfinished URLs). Disabled in tests.
  defp recovery_children do
    if Application.get_env(:seovivu, :recover_jobs_on_boot, true) do
      [
        Supervisor.child_spec({Task, &Seovivu.Seo.recover_orphaned_jobs/0},
          id: :seo_recovery,
          restart: :transient
        )
      ]
    else
      []
    end
  end

  # In dev we long-poll Telegram for updates (no public webhook). In prod the
  # webhook controller handles updates instead.
  defp telegram_children do
    if Application.get_env(:seovivu, :telegram_poller, false) do
      [Seovivu.Telegram.Poller]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SeovivuWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
