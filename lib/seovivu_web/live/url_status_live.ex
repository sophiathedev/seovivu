defmodule SeovivuWeb.UrlStatusLive do
  @moduledoc """
  Batch HTTP-status checker. Every request is routed through a random proxy so
  the VPS origin IP stays hidden.
  """
  use SeovivuWeb.BatchFeature, feature: :url_status, title: "Kiểm tra trạng thái URL"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      current_user={@current_user}
      active={:url_status}
      page_title="Kiểm tra trạng thái URL"
      flash={@flash}
      credits={@credits}
      days={@days}
    >
      <div class="mb-6">
        <h2 class="text-3xl font-bold tracking-tight text-ink">Kiểm tra trạng thái URL</h2>
        <p class="mt-1 text-ink-muted">
          Kiểm tra mã trạng thái HTTP hàng loạt qua proxy (ẩn IP máy chủ).
          <span class="font-semibold text-success">Miễn phí — không trừ credit.</span>
        </p>
      </div>

      <div class="space-y-6">
        <BatchFeature.url_form
          form={@form}
          feature={@feature}
          pending_count={@pending_count}
          running={running?(@job)}
        />

        <BatchFeature.progress :if={@job} job={@job} />

        <div :if={@job} class="space-y-3">
          <BatchFeature.results_header />
          <.table id="url-status-items" rows={@streams.items}>
            <:col :let={{_id, item}} label="URL">
              <span class="break-all">{item.url}</span>
            </:col>
            <:col :let={{_id, item}} label="Trạng thái">
              <BatchFeature.status_badge status={item.status} />
            </:col>
            <:col :let={{_id, item}} label="Mã HTTP">{result_label(item)}</:col>
            <:col :let={{_id, item}} label="Độ trễ">{latency(item)}</:col>
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

  def copy_line(%{url: url, status: :success, result: %{"http_status" => code}, latency_ms: ms}),
    do: "#{url}\t#{code}\t#{ms || "?"} ms"

  def copy_line(%{url: url, status: :failed, result: result}),
    do: "#{url}\tLỗi: #{result["error"] || "lỗi"}"

  def copy_line(%{url: url}), do: "#{url}\t—"

  defp running?(%{status: :running}), do: true
  defp running?(_), do: false

  defp result_label(%{status: :success, result: %{"http_status" => code, "ok" => true}}) do
    assigns = %{code: code}
    ~H|<.badge tone="success">{@code}</.badge>|
  end

  defp result_label(%{status: :success, result: %{"http_status" => code}}) do
    assigns = %{code: code}
    ~H|<.badge tone="danger">{@code}</.badge>|
  end

  defp result_label(%{status: :failed, result: result}) do
    assigns = %{error: result["error"] || "lỗi"}
    ~H|<span class="text-sm text-danger">{@error}</span>|
  end

  defp result_label(_), do: "—"

  defp latency(%{latency_ms: ms}) when is_integer(ms), do: "#{ms} ms"
  defp latency(_), do: "—"
end
