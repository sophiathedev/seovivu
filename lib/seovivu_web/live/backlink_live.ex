defmodule SeovivuWeb.BacklinkLive do
  @moduledoc """
  Batch backlink checker: for each source URL, fetch it (through a proxy) and
  check whether it still links to the target domain, and whether the link is
  dofollow/nofollow.
  """
  use SeovivuWeb.BatchFeature, feature: :backlink, title: "Kiểm tra Backlink"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      current_user={@current_user}
      active={:backlink}
      page_title="Kiểm tra Backlink"
      flash={@flash}
      credits={@credits}
      days={@days}
    >
      <div class="mb-6">
        <h2 class="text-3xl font-bold tracking-tight text-ink">Kiểm tra Backlink</h2>
        <p class="mt-1 text-ink-muted">
          Kiểm tra các trang nguồn còn trỏ link về tên miền của bạn hay không (qua proxy).
          <span class="font-semibold text-success">Miễn phí — không trừ credit.</span>
        </p>
      </div>

      <div class="space-y-6">
        <BatchFeature.url_form
          form={@form}
          feature={@feature}
          pending_count={@pending_count}
          running={running?(@job)}
          placeholder="https://trang-nguon-1.com/bai-viet\nhttps://trang-nguon-2.com/bai-viet"
        >
          <:extra>
            <.input
              name="target"
              value=""
              label="Tên miền đích (link cần tìm)"
              placeholder="vidu.com"
              required
            />
          </:extra>
        </BatchFeature.url_form>

        <BatchFeature.progress :if={@job} job={@job} />

        <div :if={@job} class="space-y-3">
          <BatchFeature.results_header />
          <.table id="backlink-items" rows={@streams.items}>
            <:col :let={{_id, item}} label="URL nguồn">
              <span class="break-all">{item.url}</span>
            </:col>
            <:col :let={{_id, item}} label="Trạng thái">
              <BatchFeature.status_badge status={item.status} />
            </:col>
            <:col :let={{_id, item}} label="Backlink">{backlink_label(item)}</:col>
            <:col :let={{_id, item}} label="Anchor text">{anchors_label(item)}</:col>
            <:action :let={{id, item}}>
              <BatchFeature.copy_button id={"copy-#{id}"} text={item.url} label="Sao chép URL" />
            </:action>
          </.table>
        </div>

        <BatchFeature.recent_jobs jobs={@jobs} />
      </div>
    </Layouts.dashboard>
    """
  end

  def copy_line(%{url: url, status: :success, result: %{"found" => true} = result}) do
    anchors = result["anchors"] || []
    texts = anchors |> Enum.map(&(&1["text"] || "")) |> Enum.reject(&(&1 == "")) |> Enum.join(", ")
    "#{url}\tCòn link (#{result["count"] || length(anchors)})\t#{texts}"
  end

  def copy_line(%{url: url, status: :success, result: %{"found" => false}}),
    do: "#{url}\tMất link"

  def copy_line(%{url: url, status: :failed, result: result}),
    do: "#{url}\tLỗi: #{result["error"] || "lỗi"}"

  def copy_line(%{url: url}), do: "#{url}\t—"

  defp running?(%{status: :running}), do: true
  defp running?(_), do: false

  defp backlink_label(%{status: :success, result: %{"found" => true, "count" => count}}) do
    assigns = %{count: count}
    ~H|<.badge tone="success">Còn link ({@count})</.badge>|
  end

  defp backlink_label(%{status: :success, result: %{"found" => false}}) do
    assigns = %{}
    ~H|<.badge tone="danger">Mất link</.badge>|
  end

  defp backlink_label(%{status: :failed, result: result}) do
    assigns = %{error: result["error"] || "lỗi"}
    ~H|<span class="text-sm text-danger">{@error}</span>|
  end

  defp backlink_label(_), do: "—"

  defp anchors_label(%{status: :success, result: %{"anchors" => [_ | _] = anchors}}) do
    assigns = %{anchors: anchors}

    ~H"""
    <ul class="space-y-1">
      <li :for={a <- @anchors} class="flex items-center gap-2">
        <span class="break-words text-sm text-ink">{anchor_text(a["text"])}</span>
        <.badge tone={if a["rel"] == "nofollow", do: "warning", else: "info"}>{a["rel"]}</.badge>
      </li>
    </ul>
    """
  end

  defp anchors_label(_), do: "—"

  defp anchor_text(""), do: "(không có text)"
  defp anchor_text(nil), do: "(không có text)"
  defp anchor_text(text), do: text
end
