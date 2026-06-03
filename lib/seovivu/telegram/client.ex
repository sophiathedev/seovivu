defmodule Seovivu.Telegram.Client do
  @moduledoc """
  Thin Req-based wrapper over the Telegram Bot API. The bot token is read from
  the DB-backed `Settings` store so it can be configured at runtime by an admin.
  """
  alias Seovivu.Settings

  @base "https://api.telegram.org"

  @doc "The configured bot token (or nil)."
  def token, do: Settings.get_value("telegram.bot_token")

  @doc "Whether a non-empty bot token is configured."
  def configured? do
    case token() do
      t when is_binary(t) and t != "" -> true
      _ -> false
    end
  end

  @doc """
  Calls a Bot API method. Returns `{:ok, result}` on success,
  `{:error, {:telegram, code, description}}` on an API error, or
  `{:error, reason}` for transport errors / missing token.
  """
  def call(method, params \\ %{}), do: call_with_token(method, params, token())

  @doc "Like `call/2` but uses an explicit token (e.g. to test an unsaved one)."
  def call_with_token(method, params, tok) when is_binary(tok) and tok != "" do
    url = "#{@base}/bot#{tok}/#{method}"

    case Req.post(url, json: params, finch: Seovivu.Finch, retry: false, receive_timeout: 35_000) do
      {:ok, %{status: 200, body: %{"ok" => true, "result" => result}}} ->
        {:ok, result}

      {:ok, %{body: %{"ok" => false} = body}} ->
        {:error, {:telegram, body["error_code"], body["description"]}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def call_with_token(_method, _params, _tok), do: {:error, :not_configured}

  def get_me, do: call("getMe")
  def get_me(token), do: call_with_token("getMe", %{}, token)

  def send_message(chat_id, text) do
    call("sendMessage", %{chat_id: chat_id, text: text, disable_web_page_preview: true})
  end

  def set_webhook(url, secret) do
    call("setWebhook", %{url: url, secret_token: secret, allowed_updates: ["message"]})
  end

  def delete_webhook, do: call("deleteWebhook", %{drop_pending_updates: false})

  def get_updates(offset, timeout \\ 0) do
    call("getUpdates", %{offset: offset, timeout: timeout, allowed_updates: ["message"]})
  end
end
