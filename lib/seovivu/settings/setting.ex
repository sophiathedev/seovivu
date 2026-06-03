defmodule Seovivu.Settings.Setting do
  @moduledoc """
  A single DB-backed configuration entry. The `value` is a JSON map so any shape
  of config (scalars, secrets, template maps) can be stored uniformly, e.g.:

    * `"telegram.bot_token"`    => `%{"value" => "123:abc"}`
    * `"telegram.bot_username"` => `%{"value" => "seovivu_bot"}`
    * `"telegram.templates"`    => `%{"welcome" => "...", "password_reset" => "..."}`
    * `"scrapingdog.api_key"`   => `%{"value" => "..."}`
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "settings" do
    field :key, :string
    field :value, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value])
    |> validate_required([:key])
    |> unique_constraint(:key)
  end
end
