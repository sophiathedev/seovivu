defmodule SeovivuWeb.Admin.OverviewLive do
  use SeovivuWeb, :live_view

  alias Seovivu.{Accounts, Billing, Indexer, Net, Seo}

  @feature_labels [
    {:check_index, "Kiểm tra Index"},
    {:url_status, "Trạng thái URL"},
    {:backlink, "Backlink"},
    {:redirect_301, "Redirect 301"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    usage = Seo.global_usage()
    credits = Billing.totals()
    index_stats = Indexer.stats()

    {:ok,
     socket
     |> assign(:page_title, "Tổng quan quản trị")
     |> assign(:total_users, Accounts.count_users())
     |> assign(:active_users, Accounts.count_users(status: :active))
     |> assign(:banned_users, Accounts.count_users(status: :banned))
     |> assign(:proxies, length(Net.list_proxies()))
     |> assign(:main_credits, credits.main)
     |> assign(:index_credits, credits.index)
     |> assign(:jobs_chart, feature_chart(usage))
     |> assign(:total_jobs, total_jobs(usage))
     |> assign(:index_chart, index_chart(index_stats))
     |> assign(:index_projects, index_stats.projects)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      current_user={@current_user}
      active={:overview}
      page_title="Tổng quan quản trị"
      flash={@flash}
    >
      <div class="mb-6">
        <h2 class="text-3xl font-bold tracking-tight text-ink">Tổng quan</h2>
        <p class="mt-1 text-ink-muted">Tình hình tổng quan của hệ thống.</p>
      </div>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <.stat_card
          icon="hero-users"
          tone="info"
          label="Tổng người dùng"
          value={fmt(@total_users)}
        />
        <.stat_card
          icon="hero-check-circle"
          tone="success"
          label="Đang hoạt động"
          value={fmt(@active_users)}
        />
        <.stat_card icon="hero-bolt" tone="warning" label="Credit chính" value={fmt(@main_credits)} />
        <.stat_card
          icon="hero-paper-airplane"
          tone="neutral"
          label="Credit Index"
          value={fmt(@index_credits)}
        />
      </div>

      <div class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <.stat_card
          icon="hero-play"
          tone="info"
          label="Tổng lượt chạy"
          value={fmt(@total_jobs)}
        />
        <.stat_card
          icon="hero-rectangle-stack"
          tone="info"
          label="Dự án Index"
          value={fmt(@index_projects)}
        />
        <.stat_card icon="hero-globe-alt" tone="success" label="Proxy" value={fmt(@proxies)} />
        <.stat_card icon="hero-no-symbol" tone="danger" label="Bị khóa" value={fmt(@banned_users)} />
      </div>

      <div class="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-2">
        <section class="rounded-card border border-line bg-surface p-6 shadow-card">
          <h3 class="mb-4 text-sm font-bold uppercase tracking-wider text-ink-secondary">
            Lượt chạy theo công cụ
          </h3>
          <.bar_chart items={@jobs_chart} />
        </section>

        <section class="rounded-card border border-line bg-surface p-6 shadow-card">
          <h3 class="mb-4 text-sm font-bold uppercase tracking-wider text-ink-secondary">
            Dự án Gửi Index theo trạng thái
          </h3>
          <.bar_chart items={@index_chart} />
        </section>
      </div>
    </Layouts.admin>
    """
  end

  defp feature_chart(usage) do
    Enum.map(@feature_labels, fn {feature, label} ->
      %{label: label, value: get_in(usage, [feature, :jobs]) || 0}
    end)
  end

  defp total_jobs(usage), do: usage |> Enum.map(fn {_f, s} -> s.jobs end) |> Enum.sum()

  defp index_chart(%{by_status: by_status}) do
    [
      %{label: "Đã gửi", value: Map.get(by_status, :submitted, 0)},
      %{label: "Đang xử lý", value: Map.get(by_status, :processing, 0)},
      %{label: "Hoàn tất", value: Map.get(by_status, :done, 0)}
    ]
  end

  defp fmt(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp fmt(other), do: to_string(other)
end
