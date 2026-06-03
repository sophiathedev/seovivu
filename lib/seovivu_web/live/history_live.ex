defmodule SeovivuWeb.HistoryLive do
  @moduledoc """
  The user's own activity history: usage totals per feature, recent batch jobs,
  and login history (IP + device).
  """
  use SeovivuWeb, :live_view

  alias Seovivu.{Accounts, Billing, Repo, Seo}

  @feature_labels %{
    check_index: "Kiểm tra Index",
    url_status: "Trạng thái URL",
    backlink: "Backlink",
    redirect_301: "Redirect 301"
  }

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    main = user.id |> Billing.get_wallet(:main) |> Repo.preload(:current_package)
    summary = Seo.usage_summary(user.id)

    {:ok,
     socket
     |> assign(:page_title, "Lịch sử")
     |> assign(:credits, credits(main))
     |> assign(:days, days(main))
     |> assign(:totals, totals(summary))
     |> assign(:jobs, Seo.list_recent_jobs(user.id))
     |> assign(:logins, Accounts.list_login_logs(user.id, 30))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      current_user={@current_user}
      active={:history}
      page_title="Lịch sử"
      flash={@flash}
      credits={@credits}
      days={@days}
    >
      <div class="mb-6">
        <h2 class="text-3xl font-bold tracking-tight text-ink">Lịch sử hoạt động</h2>
        <p class="mt-1 text-ink-muted">
          Thống kê sử dụng, các lượt chạy gần đây và lịch sử đăng nhập.
        </p>
      </div>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <.stat_card
          icon="hero-play"
          tone="info"
          label="Tổng lượt chạy"
          value={fmt(@totals.jobs)}
        />
        <.stat_card icon="hero-link" tone="neutral" label="Tổng URL" value={fmt(@totals.urls)} />
        <.stat_card
          icon="hero-check-circle"
          tone="success"
          label="Thành công"
          value={fmt(@totals.success)}
        />
        <.stat_card
          icon="hero-x-circle"
          tone="danger"
          label="Lỗi"
          value={fmt(@totals.failed)}
        />
      </div>

      <h3 class="mt-8 mb-3 text-sm font-bold uppercase tracking-wider text-ink-secondary">
        Lượt chạy gần đây
      </h3>
      <.table :if={@jobs != []} id="history-jobs" rows={@jobs}>
        <:col :let={j} label="Công cụ">{feature_label(j.feature)}</:col>
        <:col :let={j} label="Tổng">{j.total}</:col>
        <:col :let={j} label="Thành công">{j.success_count}</:col>
        <:col :let={j} label="Lỗi">{j.failed_count}</:col>
        <:col :let={j} label="Trạng thái">
          <.badge tone={job_tone(j.status)}>{job_status(j.status)}</.badge>
        </:col>
        <:col :let={j} label="Thời gian">{datetime(j.completed_at || j.inserted_at)}</:col>
      </.table>
      <p
        :if={@jobs == []}
        class="rounded-card border border-line bg-surface px-3 py-10 text-center text-sm text-ink-muted shadow-soft"
      >
        Chưa có lượt chạy nào.
      </p>

      <h3 class="mt-8 mb-3 text-sm font-bold uppercase tracking-wider text-ink-secondary">
        Lịch sử đăng nhập
      </h3>
      <.table :if={@logins != []} id="history-logins" rows={@logins}>
        <:col :let={l} label="Thời gian">{datetime(l.inserted_at)}</:col>
        <:col :let={l} label="Địa chỉ IP">{l.ip_address || "-"}</:col>
        <:col :let={l} label="Thiết bị">
          <span class="block max-w-md truncate text-ink-muted">{l.user_agent || "-"}</span>
        </:col>
      </.table>
      <p
        :if={@logins == []}
        class="rounded-card border border-line bg-surface px-3 py-10 text-center text-sm text-ink-muted shadow-soft"
      >
        Chưa có lần đăng nhập nào được ghi nhận.
      </p>
    </Layouts.dashboard>
    """
  end

  defp totals(summary) do
    Enum.reduce(summary, %{jobs: 0, urls: 0, success: 0, failed: 0}, fn {_f, s}, acc ->
      %{
        jobs: acc.jobs + (s.jobs || 0),
        urls: acc.urls + (s.urls || 0),
        success: acc.success + (s.success || 0),
        failed: acc.failed + (s.failed || 0)
      }
    end)
  end

  defp feature_label(feature), do: Map.get(@feature_labels, feature, to_string(feature))

  defp job_status(:done), do: "Hoàn tất"
  defp job_status(:running), do: "Đang chạy"
  defp job_status(:canceled), do: "Đã hủy"
  defp job_status(other), do: to_string(other)

  defp job_tone(:done), do: "success"
  defp job_tone(:running), do: "info"
  defp job_tone(_), do: "neutral"

  defp credits(nil), do: 0
  defp credits(%{credits: c}), do: c
  defp days(nil), do: 0
  defp days(wallet), do: Billing.days_remaining(wallet)

  defp fmt(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp fmt(other), do: to_string(other)
end
