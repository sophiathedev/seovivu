defmodule Seovivu.Telegram do
  @moduledoc """
  Telegram bot integration: registration/linking, password delivery, command
  handling, and webhook management.

  Incoming updates arrive via `SeovivuWeb.TelegramController` (webhook, prod) or
  `Seovivu.Telegram.Poller` (long-poll, dev) and are funneled through
  `handle_update/1`. Outgoing messages are sent asynchronously through
  `Seovivu.Telegram.Workers.SendMessageWorker` so a slow/failing Bot API never
  blocks the caller.
  """
  require Logger

  alias Seovivu.{Accounts, Settings}
  alias Seovivu.Telegram.Client
  alias Seovivu.Telegram.Workers.{BroadcastWorker, SendMessageWorker}

  @pubsub Seovivu.PubSub

  @default_templates %{
    "welcome" => """
    Chào mừng đến với Bộ công cụ SEO! Tài khoản của bạn đã sẵn sàng.

    Tên đăng nhập: {{username}}
    Mật khẩu: {{password}}

    Hãy đăng nhập trên website bằng thông tin này. Dùng /reset bất cứ lúc nào để lấy mật khẩu mới.
    """,
    "already_registered" => """
    Bạn đã đăng ký với tên {{username}}.

    Quên mật khẩu? Gửi /reset và mình sẽ gửi mật khẩu mới cho bạn.
    """,
    "reset" => """
    Đây là mật khẩu mới của bạn:

    {{password}}

    Hãy đăng nhập trên website bằng mật khẩu này.
    """
  }

  ## Configuration / status

  defdelegate configured?, to: Client

  @doc """
  Calls getMe to verify a bot token; on success caches the bot username. Pass a
  token to test one straight from the input (without saving); omit to use the
  saved token.
  """
  def test_connection(token \\ nil) do
    result = if token in [nil, ""], do: Client.get_me(), else: Client.get_me(token)

    case result do
      {:ok, %{"username" => username} = me} when is_binary(username) ->
        Settings.put_value("telegram.bot_username", username)
        {:ok, me}

      {:ok, me} ->
        {:ok, me}

      error ->
        error
    end
  end

  def bot_username, do: Settings.get_value("telegram.bot_username")

  @doc "Builds the `t.me` deep link that links a Telegram user to a web registration."
  def deep_link(nonce) when is_binary(nonce) do
    case bot_username() do
      u when is_binary(u) and u != "" -> {:ok, "https://t.me/#{u}?start=#{nonce}"}
      _ -> :error
    end
  end

  ## Webhook management

  @doc "Returns the stored webhook secret, generating one on first use."
  def webhook_secret do
    case Settings.get_value("telegram.webhook_secret") do
      s when is_binary(s) and s != "" ->
        s

      _ ->
        secret = :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
        Settings.put_value("telegram.webhook_secret", secret)
        secret
    end
  end

  @doc "Whether a webhook is currently active (so the dev poller stands down)."
  def webhook_active?, do: Settings.get_value("telegram.webhook_active", false) == true

  @doc "Marks the webhook active/inactive (used by the poller on conflict)."
  def set_webhook_active(active?),
    do: Settings.put_value("telegram.webhook_active", active? == true)

  @doc """
  Registers the webhook at `<base_url>/telegram/webhook/<secret>`.
  `base_url` should be the public HTTPS origin (e.g. https://seovivu.com).
  """
  def set_webhook(base_url) do
    secret = webhook_secret()
    base = String.trim_trailing(base_url, "/")
    url = "#{base}/telegram/webhook/#{secret}"

    case Client.set_webhook(url, secret) do
      {:ok, _} = ok ->
        Settings.put_value("telegram.webhook_base_url", base)
        set_webhook_active(true)
        ok

      other ->
        other
    end
  end

  @doc "The public base URL used for the webhook (or nil)."
  def webhook_base_url, do: Settings.get_value("telegram.webhook_base_url")

  @doc "Removes the webhook so updates can be received via long-polling again."
  def delete_webhook do
    case Client.delete_webhook() do
      {:ok, _} = ok ->
        set_webhook_active(false)
        ok

      other ->
        other
    end
  end

  ## Message templates

  @doc "The editable template keys."
  def template_keys, do: Map.keys(@default_templates)

  @doc "Built-in default templates (used when an admin hasn't customized one)."
  def default_templates, do: @default_templates

  @doc "The current template for `key` (admin override, or the built-in default)."
  def get_template(key) do
    case Settings.get_value("telegram.template.#{key}") do
      value when is_binary(value) and value != "" -> value
      _ -> Map.get(@default_templates, key, "")
    end
  end

  @doc "Stores a customized template (only known keys are accepted)."
  def put_template(key, value) when is_binary(value) do
    if key in template_keys() do
      Settings.put_value("telegram.template.#{key}", value)
      :ok
    else
      {:error, :unknown_template}
    end
  end

  @doc "Renders template `key`, substituting `{{var}}` placeholders from `vars`."
  def render_template(key, vars) when is_map(vars) do
    Enum.reduce(vars, get_template(key), fn {k, v}, acc ->
      String.replace(acc, "{{#{k}}}", to_string(v))
    end)
    |> String.trim()
  end

  ## Outgoing

  @doc "Enqueues a message to be delivered by the Telegram worker."
  def send_message_async(chat_id, text) do
    %{chat_id: chat_id, text: text}
    |> SendMessageWorker.new()
    |> Oban.insert()
  end

  @doc """
  Issues a fresh password to every account that has none yet (e.g. users
  imported from the old WebIndex data) and DMs it to them over Telegram. Returns
  the number of accounts provisioned.
  """
  def issue_passwords_to_passwordless_users do
    users = Accounts.list_users_without_password()

    Enum.each(users, fn user ->
      case Accounts.reset_password(user) do
        {:ok, _user, password} -> send_message_async(user.telegram_id, reset_text(password))
        _ -> :ok
      end
    end)

    length(users)
  end

  @doc """
  Queues a broadcast of `text` to every active user. Returns
  `{:ok, recipient_count}` or `{:error, :empty}`. The actual fan-out (one
  message per user) happens in `BroadcastWorker`.
  """
  def broadcast(text) when is_binary(text) do
    case String.trim(text) do
      "" ->
        {:error, :empty}

      trimmed ->
        {:ok, _job} = %{text: trimmed} |> BroadcastWorker.new() |> Oban.insert()
        {:ok, length(Accounts.list_active_user_telegram_ids())}
    end
  end

  ## Incoming updates

  @doc "Entry point for an incoming update map (webhook or poller)."
  def handle_update(%{"message" => %{"text" => text} = message}) when is_binary(text) do
    handle_command(String.trim(text), message)
  end

  def handle_update(_update), do: :ignore

  defp handle_command("/start" <> rest, message) do
    nonce = rest |> String.trim() |> presence()
    chat_id = get_in(message, ["chat", "id"])
    from = message["from"] || %{}

    attrs = %{
      telegram_id: from["id"],
      telegram_username: from["username"],
      telegram_first_name: from["first_name"],
      telegram_last_name: from["last_name"]
    }

    case Accounts.register_via_telegram(attrs) do
      {:ok, %{user: user, password: nil}} ->
        send_message_async(chat_id, already_registered_text(user))
        broadcast_linked(nonce, user)
        :ok

      {:ok, %{user: user, password: password}} ->
        send_message_async(chat_id, welcome_text(user, password))
        broadcast_linked(nonce, user)
        :ok

      {:error, reason} ->
        Logger.warning("Telegram registration failed: #{inspect(reason)}")

        send_message_async(
          chat_id,
          "Xin lỗi, đã có lỗi khi tạo tài khoản. Vui lòng thử lại /start."
        )

        :ok
    end
  end

  defp handle_command("/reset" <> _, message) do
    chat_id = get_in(message, ["chat", "id"])

    case Accounts.get_user_by_telegram_id(get_in(message, ["from", "id"])) do
      nil ->
        send_message_async(chat_id, "Bạn chưa có tài khoản. Gửi /start để tạo tài khoản.")

      user ->
        case Accounts.reset_password(user) do
          {:ok, _user, password} -> send_message_async(chat_id, reset_text(password))
          _ -> send_message_async(chat_id, "Không đặt lại được mật khẩu. Vui lòng thử lại.")
        end
    end

    :ok
  end

  defp handle_command("/changepass" <> rest, message) do
    chat_id = get_in(message, ["chat", "id"])
    user = Accounts.get_user_by_telegram_id(get_in(message, ["from", "id"]))
    new_password = String.trim(rest)

    cond do
      is_nil(user) ->
        send_message_async(chat_id, "Bạn chưa có tài khoản. Gửi /start để tạo tài khoản.")

      String.length(new_password) < 8 ->
        send_message_async(chat_id, "Cú pháp: /changepass <mật khẩu mới> (ít nhất 8 ký tự).")

      true ->
        case Accounts.set_password(user, new_password) do
          {:ok, _} -> send_message_async(chat_id, "Mật khẩu của bạn đã được cập nhật.")
          _ -> send_message_async(chat_id, "Không cập nhật được mật khẩu. Vui lòng thử lại.")
        end
    end

    :ok
  end

  defp handle_command(_other, message) do
    send_message_async(get_in(message, ["chat", "id"]), help_text())
    :ok
  end

  ## Messages

  defp welcome_text(user, password) do
    render_template("welcome", %{username: display_name(user), password: password})
  end

  defp already_registered_text(user) do
    render_template("already_registered", %{username: display_name(user)})
  end

  defp reset_text(password) do
    render_template("reset", %{password: password})
  end

  defp display_name(user), do: user.username || user.telegram_username

  defp help_text do
    """
    Các lệnh của bot Bộ công cụ SEO:

    /start - tạo tài khoản / liên kết cuộc trò chuyện này
    /reset - lấy mật khẩu mới
    /changepass <mật khẩu mới> - tự đặt mật khẩu
    """
  end

  ## Helpers

  defp broadcast_linked(nil, _user), do: :ok

  defp broadcast_linked(nonce, user) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "register:#{nonce}",
      {:telegram_linked, %{username: user.username}}
    )
  end

  defp presence(""), do: nil
  defp presence(value), do: value
end
