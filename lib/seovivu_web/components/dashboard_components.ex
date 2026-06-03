defmodule SeovivuWeb.DashboardComponents do
  @moduledoc """
  Presentational building blocks for the dashboard surfaces: status badges,
  metric stat cards, and dependency-free SVG donut charts. All styling is driven
  by the design tokens defined in `assets/css/app.css`.
  """
  use Phoenix.Component

  import SeovivuWeb.CoreComponents, only: [icon: 1]

  @doc """
  A small status pill. Tone maps to the success/danger/warning/info palette.

      <.badge tone="success">Active</.badge>
      <.badge tone="danger">Banned</.badge>
  """
  attr :tone, :string, default: "neutral", values: ~w(success danger warning info neutral)
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def badge(assigns) do
    tones = %{
      "success" => "bg-success-bg text-success border-success-border",
      "danger" => "bg-danger-bg text-danger border-danger-border",
      "warning" => "bg-warning-bg text-warning border-warning",
      "info" => "bg-info-bg text-info border-accent-soft",
      "neutral" => "bg-page text-ink-secondary border-line"
    }

    assigns = assign(assigns, :tone_class, Map.fetch!(tones, assigns.tone))

    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 rounded-badge border px-3 py-1 text-xs font-semibold",
      @tone_class,
      @class
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  An in-place on/off toggle switch. Fires `on_click` (carrying `phx-value-id`)
  to flip the state on the server.

      <.toggle on={p.active} on_click="toggle_active" id={p.id} />
  """
  attr :on, :boolean, required: true
  attr :on_click, :string, required: true
  attr :id, :any, required: true
  attr :label_on, :string, default: "Đang bật"
  attr :label_off, :string, default: "Tắt"

  def toggle(assigns) do
    ~H"""
    <button
      type="button"
      role="switch"
      aria-checked={to_string(@on)}
      phx-click={@on_click}
      phx-value-id={@id}
      class="group inline-flex cursor-pointer items-center gap-2"
    >
      <span class={[
        "relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors",
        if(@on, do: "bg-success", else: "bg-line")
      ]}>
        <span class={[
          "inline-block size-4 transform rounded-full bg-white shadow-soft transition-transform",
          if(@on, do: "translate-x-6", else: "translate-x-1")
        ]} />
      </span>
      <span class={["text-xs font-semibold", if(@on, do: "text-success", else: "text-ink-muted")]}>
        {if @on, do: @label_on, else: @label_off}
      </span>
    </button>
    """
  end

  @doc """
  A metric card: an icon chip, a large value and a label.

      <.stat_card icon="hero-bolt" label="Credits" value="12,450" tone="info" />
  """
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :tone, :string, default: "info", values: ~w(success danger warning info neutral)
  attr :class, :any, default: nil

  def stat_card(assigns) do
    chips = %{
      "success" => "bg-success-bg text-success",
      "danger" => "bg-danger-bg text-danger",
      "warning" => "bg-warning-bg text-warning",
      "info" => "bg-info-bg text-info",
      "neutral" => "bg-page text-ink-secondary"
    }

    assigns = assign(assigns, :chip_class, Map.fetch!(chips, assigns.tone))

    ~H"""
    <div class={[
      "flex items-center gap-4 rounded-card border border-line bg-surface p-5 shadow-soft",
      @class
    ]}>
      <span class={["flex size-11 shrink-0 items-center justify-center rounded-md", @chip_class]}>
        <.icon name={@icon} class="size-5" />
      </span>
      <div class="min-w-0">
        <p class="truncate text-2xl font-bold leading-tight text-ink">{@value}</p>
        <p class="truncate text-sm text-ink-muted">{@label}</p>
      </div>
    </div>
    """
  end

  @doc """
  A dependency-free horizontal bar chart. `items` is a list of
  `%{label: ..., value: integer}`; bars are scaled to the largest value.

      <.bar_chart items={[%{label: "A", value: 10}, %{label: "B", value: 4}]} />
  """
  attr :items, :list, required: true
  attr :class, :any, default: nil

  def bar_chart(assigns) do
    max = assigns.items |> Enum.map(& &1.value) |> Enum.max(fn -> 0 end)
    assigns = assign(assigns, :max, max)

    ~H"""
    <div class={["space-y-3", @class]}>
      <div :if={@items == []} class="py-6 text-center text-sm text-ink-muted">Chưa có dữ liệu.</div>
      <div :for={item <- @items} class="flex items-center gap-3">
        <span class="w-40 shrink-0 truncate text-sm text-ink-secondary">{item.label}</span>
        <div class="h-2.5 flex-1 overflow-hidden rounded-full bg-page">
          <div class="h-full rounded-full bg-brand" style={"width: #{pct(item.value, @max)}%"}></div>
        </div>
        <span class="w-12 shrink-0 text-right text-sm font-semibold text-ink">{item.value}</span>
      </div>
    </div>
    """
  end

  defp pct(_value, 0), do: 0
  defp pct(value, max), do: round(value / max * 100)

  @doc """
  A dependency-free SVG donut chart showing a single percentage.

      <.donut percent={72} label="72%" sublabel="Credits used" />

  `color`/`track` accept any CSS color (default to the accent + line tokens).
  """
  attr :percent, :integer, required: true
  attr :label, :string, default: nil
  attr :sublabel, :string, default: nil
  attr :color, :string, default: "var(--color-accent)"
  attr :track, :string, default: "var(--color-line)"
  attr :class, :any, default: nil

  def donut(assigns) do
    radius = 42
    circumference = 2 * :math.pi() * radius
    pct = assigns.percent |> max(0) |> min(100)
    offset = circumference * (1 - pct / 100)

    assigns =
      assigns
      |> assign(:radius, radius)
      |> assign(:circumference, Float.round(circumference, 2))
      |> assign(:offset, Float.round(offset, 2))

    ~H"""
    <div class={["relative inline-grid place-items-center", @class]}>
      <svg viewBox="0 0 100 100" class="size-32 -rotate-90">
        <circle cx="50" cy="50" r={@radius} fill="none" stroke={@track} stroke-width="12" />
        <circle
          cx="50"
          cy="50"
          r={@radius}
          fill="none"
          stroke={@color}
          stroke-width="12"
          stroke-linecap="round"
          stroke-dasharray={@circumference}
          stroke-dashoffset={@offset}
        />
      </svg>
      <div class="absolute text-center">
        <div :if={@label} class="text-xl font-bold text-ink">{@label}</div>
        <div :if={@sublabel} class="text-xs text-ink-muted">{@sublabel}</div>
      </div>
    </div>
    """
  end
end
