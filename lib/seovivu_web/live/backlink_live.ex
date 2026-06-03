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
          Kiểm tra các trang nguồn còn trỏ link về tên miền của bạn hay không (qua proxy). Mỗi URL tốn 1 credit.
        </p>
      </div>

      <div class="space-y-6">
        <BatchFeature.url_form
          form={@form}
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

        <.table :if={@job} id="backlink-items" rows={@streams.items}>
          <:col :let={{_id, item}} label="URL nguồn">
            <span class="break-all">{item.url}</span>
          </:col>
          <:col :let={{_id, item}} label="Trạng thái">
            <BatchFeature.status_badge status={item.status} />
          </:col>
          <:col :let={{_id, item}} label="Backlink">{backlink_label(item)}</:col>
          <:col :let={{_id, item}} label="Anchor text">{anchors_label(item)}</:col>
        </.table>
      </div>
    </Layouts.dashboard>
    """
  end

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
