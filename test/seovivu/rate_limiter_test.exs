defmodule Seovivu.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Seovivu.RateLimiter

  # Unique key per assertion so concurrent tests never share a bucket.
  defp uniq, do: {:test, System.unique_integer([:positive])}

  test "allows up to the limit, then blocks within the window" do
    key = uniq()
    assert RateLimiter.hit(key, 2, 60_000) == :ok
    assert RateLimiter.hit(key, 2, 60_000) == :ok
    assert RateLimiter.hit(key, 2, 60_000) == {:error, :rate_limited}
  end

  test "separate keys have independent budgets" do
    assert RateLimiter.hit(uniq(), 1, 60_000) == :ok
    assert RateLimiter.hit(uniq(), 1, 60_000) == :ok
  end

  test "a fresh window after expiry allows again" do
    key = uniq()
    assert RateLimiter.hit(key, 1, 1) == :ok
    Process.sleep(5)
    assert RateLimiter.hit(key, 1, 1) == :ok
  end

  test "reset/1 forgets a key" do
    key = uniq()
    assert RateLimiter.hit(key, 1, 60_000) == :ok
    assert RateLimiter.hit(key, 1, 60_000) == {:error, :rate_limited}
    RateLimiter.reset(key)
    assert RateLimiter.hit(key, 1, 60_000) == :ok
  end
end
