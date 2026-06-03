defmodule SeovivuWeb.DisavowLive do
  @moduledoc """
  Generates a Google Disavow file from a list of domains/URLs. Pure client-side
  generation — no credits, no network.
  """
  use SeovivuWeb, :live_view

  alias Seovivu.{Billing, Repo}

  @impl true
  def mount(_params, _session, socket) do
    main =
      socket.assigns.current_user.id
      |> Billing.get_wallet(:main)
      |> Repo.preload(:current_package)

    {:ok,
     socket
     |> assign(:page_title, "Disavow Link")
     |> assign(:credits, credits(main))
     |> assign(:days, days(main))
     |> assign(:input, "")
     |> assign(:as_domain, true)
     |> assign(:output, "")}
  end

  @impl true
  def handle_event("generate", params, socket) do
    input = Map.get(params, "input", "")
    as_domain = Map.get(params, "as_domain", "true") == "true"

    {:noreply,
     socket
     |> assign(:input, input)
     |> assign(:as_domain, as_domain)
     |> assign(:output, build(input, as_domain))}
  end

  defp build(input, as_domain) do
    input
    |> String.split(["\n", "\r\n"])
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn line -> if as_domain, do: "domain:" <> host_of(line), else: line end)
    |> Enum.reject(&(&1 == "domain:"))
    |> Enum.uniq()
    |> Enum.join("\n")
  end

  defp host_of(line) do
    line
    |> String.replace(~r{^https?://}i, "")
    |> String.replace(~r{/.*$}, "")
    |> String.trim_trailing("/")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      current_user={@current_user}
      active={:disavow}
      page_title="Disavow Link"
      flash={@flash}
      credits={@credits}
      days={@days}
    >
      <div class="mb-6">
        <h2 class="text-3xl font-bold tracking-tight text-ink">Disavow Link</h2>
        <p class="mt-1 text-ink-muted">
          Tạo file disavow để tải lên Google Search Console. Miễn phí, không tốn credit.
        </p>
      </div>

      <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <section class="rounded-card border border-line bg-surface p-6 shadow-card">
          <form phx-change="generate">
            <.input
              name="input"
              type="textarea"
              rows="12"
              value={@input}
              label="Danh sách tên miền / URL (mỗi dòng một mục)"
              placeholder="spam-site.com\nhttps://xau.example.net/trang"
            />
            <.input
              name="as_domain"
              type="checkbox"
              checked={@as_domain}
              label="Chặn cả tên miền (thêm tiền tố domain:)"
            />
          </form>
        </section>

        <section class="rounded-card border border-line bg-surface p-6 shadow-card">
          <div class="mb-2 flex items-center justify-between">
            <h3 class="text-sm font-bold uppercase tracking-wider text-ink-secondary">Kết quả</h3>
            <div :if={@output != ""} class="flex gap-2">
              <.button
                type="button"
                variant="secondary"
                onclick="navigator.clipboard.writeText(document.getElementById('disavow-output').value)"
              >
                <.icon name="hero-clipboard" class="size-4" /> Sao chép
              </.button>
              <a
                href={"data:text/plain;charset=utf-8," <> URI.encode(@output)}
                download="disavow.txt"
                class="inline-flex h-9 items-center justify-center gap-1.5 rounded-button border border-brand bg-brand px-3.5 text-sm font-semibold text-white shadow-button hover:bg-brand-hover"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" /> Tải xuống
              </a>
            </div>
          </div>
          <textarea
            id="disavow-output"
            readonly
            rows="12"
            class="block w-full rounded-button border border-line bg-page px-3 py-2 font-mono text-sm text-ink"
          >{@output}</textarea>
        </section>
      </div>
    </Layouts.dashboard>
    """
  end

  defp credits(nil), do: 0
  defp credits(%{credits: c}), do: c
  defp days(nil), do: 0
  defp days(wallet), do: Billing.days_remaining(wallet)
end
