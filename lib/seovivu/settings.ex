defmodule Seovivu.Settings do
  @moduledoc """
  DB-backed application configuration: secrets (Telegram token, ScrapingDog key),
  message templates, and per-feature concurrency limits.

  Scalar settings are cached in `:persistent_term` so hot paths (HTTP layer,
  workers) read config without hitting the database. The cache is rebuilt
  whenever a setting is written.
  """
  import Ecto.Query, warn: false

  alias Seovivu.Repo
  alias Seovivu.Settings.{Setting, FeatureConcurrency}

  @cache_key {__MODULE__, :cache}

  ## Key/value settings

  @doc "Returns the raw value map stored for `key` (or `nil`)."
  def get(key) when is_binary(key), do: Map.get(cache(), key)

  @doc """
  Returns the scalar stored under `key` (the `\"value\"` field), or `default`.
  Use for single-value settings written with `put_value/2`.
  """
  def get_value(key, default \\ nil) do
    case get(key) do
      %{"value" => value} -> value
      _ -> default
    end
  end

  @doc "Upserts a setting with an arbitrary map value and refreshes the cache."
  def put(key, %{} = value) do
    result =
      %Setting{}
      |> Setting.changeset(%{key: key, value: value})
      |> Repo.insert(
        on_conflict: [set: [value: value, updated_at: DateTime.utc_now(:second)]],
        conflict_target: :key
      )

    refresh_cache()
    result
  end

  @doc "Upserts a single scalar value (stored as `%{\"value\" => value}`)."
  def put_value(key, value), do: put(key, %{"value" => value})

  @doc "Loads all settings into a `%{key => value_map}` map, bypassing the cache."
  def all do
    Setting |> Repo.all() |> Map.new(fn s -> {s.key, s.value} end)
  end

  defp cache do
    case :persistent_term.get(@cache_key, :miss) do
      :miss -> refresh_cache()
      cached -> cached
    end
  end

  defp refresh_cache do
    map = all()
    :persistent_term.put(@cache_key, map)
    map
  end

  ## Feature concurrency

  @doc "Lists all per-feature concurrency rows, ordered by feature."
  def list_feature_concurrency do
    FeatureConcurrency |> order_by(:feature) |> Repo.all()
  end

  @doc "Returns the per-user concurrency limit for `feature` (defaults to 5)."
  def per_user_limit(feature) do
    case Repo.get_by(FeatureConcurrency, feature: feature) do
      %FeatureConcurrency{per_user_limit: limit} -> limit
      nil -> 5
    end
  end

  def change_feature_concurrency(%FeatureConcurrency{} = fc, attrs \\ %{}) do
    FeatureConcurrency.changeset(fc, attrs)
  end

  def update_feature_concurrency(%FeatureConcurrency{} = fc, attrs) do
    fc |> FeatureConcurrency.changeset(attrs) |> Repo.update()
  end

  @doc "Ensures a row exists for every known feature (idempotent; used in seeds)."
  def ensure_feature_concurrency_defaults do
    for feature <- FeatureConcurrency.features() do
      Repo.insert!(
        %FeatureConcurrency{feature: feature, per_user_limit: 5},
        on_conflict: :nothing,
        conflict_target: :feature
      )
    end

    :ok
  end
end
