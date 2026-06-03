defmodule SeovivuWeb.RobotsLive do
  @moduledoc """
  Generates a robots.txt from simple form fields. Pure client-side generation —
  no credits, no network.
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
     |> assign(:page_title, "Tạo Robots.txt")
     |> assign(:credits, credits(main))
     |> assign(:days, days(main))
     |> assign(:fields, %{
       "user_agent" => "*",
       "disallow" => "",
       "allow" => "",
       "crawl_delay" => "",
       "sitemap" => ""
     })
     |> assign(:output, build(%{"user_agent" => "*"}))}
  end

  @impl true
  def handle_event("generate", params, socket) do
    fields = Map.take(params, ["user_agent", "disallow", "allow", "crawl_delay", "sitemap"])
    {:noreply, socket |> assign(:fields, fields) |> assign(:output, build(fields))}
  end

  defp build(fields) do
    ua = blank_to(Map.get(fields, "user_agent", ""), "*")

    rules =
      ["User-agent: #{ua}"] ++
        path_lines("Disallow", Map.get(fields, "disallow", "")) ++
        path_lines("Allow", Map.get(fields, "allow", "")) ++
        crawl_delay_line(Map.get(fields, "crawl_delay", ""))

    sitemap = String.trim(Map.get(fields, "sitemap", ""))
    rules = if sitemap == "", do: rules, else: rules ++ ["", "Sitemap: #{sitemap}"]
    Enum.join(rules, "\n")
  end

  defp path_lines(directive, text) do
    text
    |> String.split(["\n", "\r\n"])
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&"#{directive}: #{&1}")
  end

  defp crawl_delay_line(value) do
    case Integer.parse(String.trim(value)) do
      {n, _} when n > 0 -> ["Crawl-delay: #{n}"]
      _ -> []
    end
  end

  defp blank_to("", default), do: default
  defp blank_to(nil, default), do: default
  defp blank_to(value, _default), do: value

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      current_user={@current_user}
      active={:robots}
      page_title="Tạo Robots.txt"
      flash={@flash}
      credits={@credits}
      days={@days}
    >
      <div class="mb-6">
        <h2 class="text-3xl font-bold tracking-tight text-ink">Tạo Robots.txt</h2>
        <p class="mt-1 text-ink-muted">
          Tạo nhanh file robots.txt cho website. Miễn phí, không tốn credit.
        </p>
      </div>

      <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <section class="rounded-card border border-line bg-surface p-6 shadow-card">
          <form phx-change="generate">
            <.input
              name="user_agent"
              value={@fields["user_agent"]}
              label="User-agent"
              placeholder="*"
            />
            <.input
              name="disallow"
              type="textarea"
              rows="5"
              value={@fields["disallow"]}
              label="Chặn (Disallow) — mỗi đường dẫn một dòng"
              placeholder="/admin\n/wp-login.php"
            />
            <.input
              name="allow"
              type="textarea"
              rows="3"
              value={@fields["allow"]}
              label="Cho phép (Allow) — mỗi đường dẫn một dòng"
              placeholder="/public"
            />
            <.input
              name="crawl_delay"
              type="number"
              min="0"
              value={@fields["crawl_delay"]}
              label="Crawl-delay (giây, tuỳ chọn)"
            />
            <.input
              name="sitemap"
              value={@fields["sitemap"]}
              label="Sitemap (tuỳ chọn)"
              placeholder="https://vidu.com/sitemap.xml"
            />
          </form>
        </section>

        <section class="rounded-card border border-line bg-surface p-6 shadow-card">
          <div class="mb-2 flex items-center justify-between">
            <h3 class="text-sm font-bold uppercase tracking-wider text-ink-secondary">robots.txt</h3>
            <div class="flex gap-2">
              <.button
                type="button"
                variant="secondary"
                onclick="navigator.clipboard.writeText(document.getElementById('robots-output').value)"
              >
                <.icon name="hero-clipboard" class="size-4" /> Sao chép
              </.button>
              <a
                href={"data:text/plain;charset=utf-8," <> URI.encode(@output)}
                download="robots.txt"
                class="inline-flex h-9 items-center justify-center gap-1.5 rounded-button border border-brand bg-brand px-3.5 text-sm font-semibold text-white shadow-button hover:bg-brand-hover"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" /> Tải xuống
              </a>
            </div>
          </div>
          <textarea
            id="robots-output"
            readonly
            rows="16"
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
