defmodule SeovivuWeb.OverviewLive do
  use SeovivuWeb, :live_view

  alias Seovivu.{Billing, Repo}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    main = user.id |> Billing.get_wallet(:main) |> Repo.preload(:current_package)
    index = Billing.get_wallet(user.id, :index)

    {:ok,
     socket
     |> assign(:page_title, "Bảng điều khiển")
     |> assign(:main, main)
     |> assign(:index, index)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      current_user={@current_user}
      active={:overview}
      page_title="Bảng điều khiển"
      flash={@flash}
      credits={fmt(credits(@main))}
      days={days(@main)}
    >
      <div class="mb-6">
        <h2 class="text-3xl font-bold tracking-tight text-ink">
          Chào mừng trở lại, {@current_user.username || @current_user.telegram_first_name || "bạn"}.
        </h2>
        <p class="mt-1 text-ink-muted">Tổng quan tài khoản của bạn.</p>
      </div>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <.stat_card icon="hero-bolt" tone="info" label="Credit chính" value={fmt(credits(@main))} />
        <.stat_card
          icon="hero-calendar-days"
          tone="success"
          label="Số ngày còn lại"
          value={Integer.to_string(days(@main))}
        />
        <.stat_card
          icon="hero-paper-airplane"
          tone="warning"
          label="Credit Index"
          value={fmt(credits(@index))}
        />
        <.stat_card icon="hero-identification" tone="neutral" label="Hạng" value={tier(@main)} />
      </div>

      <div class="mt-6 grid grid-cols-1 gap-4 lg:grid-cols-3">
        <div class="flex flex-col items-center justify-center rounded-card border border-line bg-surface p-6 shadow-card">
          <h3 class="mb-4 self-start text-sm font-bold uppercase tracking-wider text-ink-secondary">
            Gói dịch vụ
          </h3>
          <.donut
            percent={days_percent(@main)}
            label={Integer.to_string(days(@main))}
            sublabel="ngày còn lại"
          />
        </div>

        <div class="rounded-card border border-line bg-surface p-6 shadow-card lg:col-span-2">
          <h3 class="mb-4 text-sm font-bold uppercase tracking-wider text-ink-secondary">
            Công cụ của bạn
          </h3>
          <p class="text-sm text-ink-muted">
            Các công cụ SEO (Kiểm tra Index, Trạng thái URL, Backlink, Redirect 301, Disavow và
            Robots.txt) sẽ bật dần khi hoàn thiện. Gửi Index dùng gói credit riêng tại
            index.seovivu.com.
          </p>
        </div>
      </div>
    </Layouts.dashboard>
    """
  end

  defp credits(nil), do: 0
  defp credits(wallet), do: wallet.credits

  defp days(nil), do: 0
  defp days(wallet), do: Billing.days_remaining(wallet)

  defp tier(%{current_package: %{name: name}}), do: name
  defp tier(_), do: "Miễn phí"

  defp days_percent(nil), do: 0

  defp days_percent(wallet) do
    total =
      case wallet.current_package do
        %{days: d} when d > 0 -> d
        _ -> 30
      end

    wallet
    |> Billing.days_remaining()
    |> Kernel./(total)
    |> Kernel.*(100)
    |> round()
    |> min(100)
    |> max(0)
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
