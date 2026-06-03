defmodule Seovivu.Accounts.UserToken do
  @moduledoc """
  Session tokens for authenticated users.

  Follows the standard `phx.gen.auth` session-token pattern: a random token is
  stored and used to look the user up on each request. Only the `:session`
  context is used (no email/magic-link tokens, since auth is Telegram-driven).
  """
  use Ecto.Schema
  import Ecto.Query

  alias Seovivu.Accounts.UserToken

  @rand_size 32

  # Session tokens are valid for 60 days.
  @session_validity_in_days 60

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    belongs_to :user, Seovivu.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Builds a random session token tied to the given user.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %UserToken{token: token, context: "session", user_id: user.id}}
  end

  @doc """
  Query that returns the user associated with a valid, non-expired session token.
  """
  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: user

    {:ok, query}
  end

  @doc """
  Query for a token row by its raw token + context.
  """
  def by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end

  @doc """
  Query for all tokens belonging to a user, optionally filtered by contexts.
  """
  def by_user_and_contexts_query(user, :all) do
    from t in UserToken, where: t.user_id == ^user.id
  end

  def by_user_and_contexts_query(user, [_ | _] = contexts) do
    from t in UserToken, where: t.user_id == ^user.id and t.context in ^contexts
  end
end
