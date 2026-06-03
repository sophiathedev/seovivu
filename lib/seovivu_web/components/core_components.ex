defmodule SeovivuWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework.
  The design tokens (colors, radii, shadows, the GitLab Sans font) are defined
  in `assets/css/app.css` under `@theme` and exposed as utilities such as
  `bg-surface`, `text-ink`, `border-line`, `bg-brand` and `rounded-card`.
  Here are useful references:

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: SeovivuWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :autohide, :boolean, default: false, doc: "automatically dismiss the flash after a delay"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      phx-hook={if @autohide, do: "FlashAutoHide"}
      role="alert"
      class="w-full"
      {@rest}
    >
      <div class="flex items-start gap-2.5 rounded-lg border border-line bg-surface py-2.5 pr-2 pl-3 shadow-card ring-1 ring-black/[0.02]">
        <.icon
          :if={@kind == :info}
          name="hero-check-circle-mini"
          class="mt-px size-[18px] shrink-0 text-success"
        />
        <.icon
          :if={@kind == :error}
          name="hero-exclamation-circle-mini"
          class="mt-px size-[18px] shrink-0 text-danger"
        />
        <p class="min-w-0 flex-1 text-[13px] leading-snug text-ink break-words">
          <span :if={@title} class="font-semibold">{@title} </span>{msg}
        </p>
        <button
          type="button"
          class="group -m-0.5 shrink-0 cursor-pointer rounded-md p-0.5 hover:bg-surface-hover"
          aria-label={gettext("đóng")}
        >
          <.icon name="hero-x-mark-mini" class="size-4 text-ink-light group-hover:text-ink" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any
  attr :variant, :string, values: ~w(primary secondary danger ghost)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    base =
      "inline-flex items-center justify-center gap-1.5 h-9 px-3.5 rounded-button " <>
        "text-sm font-semibold transition-all duration-150 active:scale-[0.98] " <>
        "disabled:opacity-50 disabled:pointer-events-none cursor-pointer"

    # Primary is the default: buttons are primary unless a variant is given.
    primary = "bg-brand text-white border border-brand hover:bg-brand-hover shadow-button"

    variants = %{
      "primary" => primary,
      "secondary" =>
        "bg-surface text-ink border border-line-strong hover:bg-surface-hover shadow-soft",
      "danger" =>
        "bg-surface text-danger border border-danger-border hover:bg-danger-bg shadow-soft",
      "ghost" =>
        "bg-transparent text-ink-secondary border border-transparent hover:bg-surface-hover hover:text-ink",
      nil => primary
    }

    # Always apply the base + variant styling and append any caller class, so
    # passing `class=` adds to (rather than replaces) the button styling.
    assigns =
      assign(assigns, :class, [
        base,
        Map.fetch!(variants, assigns[:variant]),
        assigns[:class]
      ])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Numbered pagination with prev/next and jump-to-page buttons.

  Pushes `event` with `phx-value-page` (a 1-based page number) on click. Renders
  nothing when there is at most one page. Long ranges are collapsed with `…`.

      <.pagination page={@page} total={@total} per_page={@per_page} event="page" />
  """
  attr :page, :integer, required: true, doc: "current page, 1-based"
  attr :total, :integer, required: true, doc: "total item count"
  attr :per_page, :integer, required: true
  attr :event, :string, default: "page", doc: "phx-click event pushed with phx-value-page"
  attr :target, :any, default: nil, doc: "optional phx-target for LiveComponents"

  def pagination(assigns) do
    total_pages = max(1, div(assigns.total + assigns.per_page - 1, assigns.per_page))

    assigns =
      assign(assigns,
        total_pages: total_pages,
        pages: page_window(assigns.page, total_pages)
      )

    ~H"""
    <nav
      :if={@total_pages > 1}
      class="flex items-center justify-center gap-1.5"
      aria-label="Phân trang"
    >
      <button
        type="button"
        phx-click={@event}
        phx-value-page={@page - 1}
        phx-target={@target}
        disabled={@page <= 1}
        aria-label="Trang trước"
        class="inline-flex size-9 cursor-pointer items-center justify-center rounded-button border border-line bg-surface text-ink-secondary transition-colors hover:bg-surface-hover hover:text-ink disabled:opacity-40 disabled:pointer-events-none"
      >
        <.icon name="hero-chevron-left" class="size-4" />
      </button>

      <%= for p <- @pages do %>
        <span :if={p == :gap} class="px-1 text-ink-light select-none">…</span>
        <button
          :if={p != :gap}
          type="button"
          phx-click={@event}
          phx-value-page={p}
          phx-target={@target}
          aria-current={p == @page && "page"}
          class={[
            "inline-flex size-9 cursor-pointer items-center justify-center rounded-button border text-sm font-semibold transition-colors",
            (p == @page && "border-brand bg-brand text-white") ||
              "border-line bg-surface text-ink hover:bg-surface-hover"
          ]}
        >
          {p}
        </button>
      <% end %>

      <button
        type="button"
        phx-click={@event}
        phx-value-page={@page + 1}
        phx-target={@target}
        disabled={@page >= @total_pages}
        aria-label="Trang sau"
        class="inline-flex size-9 cursor-pointer items-center justify-center rounded-button border border-line bg-surface text-ink-secondary transition-colors hover:bg-surface-hover hover:text-ink disabled:opacity-40 disabled:pointer-events-none"
      >
        <.icon name="hero-chevron-right" class="size-4" />
      </button>
    </nav>
    """
  end

  # Page numbers to show: always first & last, plus the current page and its
  # neighbours, with `:gap` markers where pages are skipped. e.g. for page 5 of
  # 10 -> [1, :gap, 4, 5, 6, :gap, 10].
  defp page_window(current, total) do
    [1, current - 1, current, current + 1, total]
    |> Enum.filter(&(&1 >= 1 and &1 <= total))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.reduce({[], nil}, fn p, {acc, prev} ->
      cond do
        is_nil(prev) -> {[p], p}
        p - prev == 1 -> {acc ++ [p], p}
        true -> {acc ++ [:gap, p], p}
      end
    end)
    |> elem(0)
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="mb-3">
      <label for={@id} class="flex cursor-pointer items-center gap-2 text-sm text-ink">
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={
            @class ||
              "size-[18px] cursor-pointer rounded border-line-strong text-accent focus:ring-2 focus:ring-accent/30"
          }
          {@rest}
        />{@label}
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="mb-3">
      <label for={@id}>
        <span :if={@label} class="mb-1 block text-sm font-medium text-ink-secondary">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[
            @class ||
              "block w-full rounded-button border border-line bg-surface px-3 py-2 text-sm text-ink shadow-soft focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent/30",
            @errors != [] &&
              (@error_class || "border-danger focus:border-danger focus:ring-danger/30")
          ]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="mb-3">
      <label for={@id}>
        <span :if={@label} class="mb-1 block text-sm font-medium text-ink-secondary">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class ||
              "block w-full rounded-button border border-line bg-surface px-3 py-2 text-sm text-ink shadow-soft placeholder:text-ink-light focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent/30",
            @errors != [] &&
              (@error_class || "border-danger focus:border-danger focus:ring-danger/30")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="mb-3">
      <label for={@id}>
        <span :if={@label} class="mb-1 block text-sm font-medium text-ink-secondary">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class ||
              "block w-full rounded-button border border-line bg-surface px-3 py-2 text-sm text-ink shadow-soft placeholder:text-ink-light focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent/30",
            @errors != [] &&
              (@error_class || "border-danger focus:border-danger focus:ring-danger/30")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-danger">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[
      @actions != [] && "flex items-center justify-between gap-6",
      "border-b border-line pb-4"
    ]}>
      <div>
        <h1 class="text-2xl font-bold leading-9 tracking-tight text-ink">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-ink-muted">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-hidden rounded-card border border-line bg-surface shadow-card">
      <table class="w-full border-collapse">
        <thead>
          <tr class="border-b border-line">
            <th
              :for={col <- @col}
              class="px-7 py-4 text-left text-xs font-bold uppercase tracking-wider text-ink-secondary"
            >
              {col[:label]}
            </th>
            <th :if={@action != []} class="px-7 py-4">
              <span class="sr-only">{gettext("Hành động")}</span>
            </th>
          </tr>
        </thead>
        <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
          <tr
            :for={row <- @rows}
            id={@row_id && @row_id.(row)}
            class="border-b border-line-soft last:border-0 hover:bg-page"
          >
            <td
              :for={col <- @col}
              phx-click={@row_click && @row_click.(row)}
              class={["px-7 py-5 align-middle text-sm text-ink", @row_click && "cursor-pointer"]}
            >
              {render_slot(col, @row_item.(row))}
            </td>
            <td :if={@action != []} class="w-0 px-7 py-5 font-semibold whitespace-nowrap">
              <div class="flex items-center gap-4 whitespace-nowrap">
                <%= for action <- @action do %>
                  {render_slot(action, @row_item.(row))}
                <% end %>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="divide-y divide-line-soft rounded-card border border-line bg-surface">
      <li :for={item <- @item} class="flex gap-4 px-5 py-4">
        <div class="flex-grow">
          <div class="font-bold text-ink">{item.title}</div>
          <div class="text-ink-secondary">{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(SeovivuWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(SeovivuWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
