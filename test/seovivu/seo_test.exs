defmodule Seovivu.SeoTest do
  use Seovivu.DataCase, async: true

  alias Seovivu.{Accounts, Billing, Seo}
  alias Seovivu.Accounts.User

  defp user_with_credits(credits) do
    {:ok, user} =
      %User{}
      |> User.telegram_changeset(%{
        telegram_id: System.unique_integer([:positive]),
        telegram_username: "u",
        telegram_first_name: "U",
        username: "u#{System.unique_integer([:positive])}",
        role: :user
      })
      |> Repo.insert()

    Billing.ensure_wallets(user.id)
    {:ok, _} = Billing.admin_adjust(Billing.get_wallet(user.id, :main), credits)
    Accounts.get_user!(user.id)
  end

  defp main_credits(user), do: Billing.get_wallet(user.id, :main).credits

  describe "start_batch/3" do
    test "reserves credits and creates the job + one item per URL" do
      user = user_with_credits(10)

      {:ok, job} = Seo.start_batch(user, :check_index, "a.com\nb.com\nc.com")

      assert job.total == 3
      assert job.credits_charged == 3
      assert job.status == :running
      assert main_credits(user) == 7
      assert length(Seo.list_items(job.id)) == 3
    end

    test "de-duplicates and trims URLs before charging" do
      user = user_with_credits(10)

      {:ok, job} = Seo.start_batch(user, :check_index, "  a.com \nb.com\na.com\n\n")

      assert job.total == 2
      assert main_credits(user) == 8
    end

    test "rejects an empty list without charging" do
      user = user_with_credits(10)
      assert {:error, :no_urls} = Seo.start_batch(user, :check_index, "   \n  \n")
      assert main_credits(user) == 10
    end

    test "refuses when credits are insufficient and leaves the balance untouched" do
      user = user_with_credits(2)
      assert {:error, :insufficient_credits} = Seo.start_batch(user, :check_index, "a\nb\nc")
      assert main_credits(user) == 2
    end

    test "rejects an unknown feature" do
      user = user_with_credits(10)
      assert {:error, :unknown_feature} = Seo.start_batch(user, :nope, "a\nb")
    end

    test "stores extra params (e.g. backlink target) on the job" do
      user = user_with_credits(10)

      {:ok, job} =
        Seo.start_batch(user, :backlink, "src1.com\nsrc2.com", %{"target" => "vidu.com"})

      assert job.feature == :backlink
      assert job.params == %{"target" => "vidu.com"}
    end

    test "free features (url_status, backlink) reserve no credits" do
      assert Seo.free?(:url_status)
      assert Seo.free?(:backlink)
      refute Seo.free?(:check_index)

      user = user_with_credits(10)

      {:ok, status_job} = Seo.start_batch(user, :url_status, "a.com\nb.com")
      assert status_job.credits_charged == 0
      assert main_credits(user) == 10

      {:ok, link_job} =
        Seo.start_batch(user, :backlink, "src1.com\nsrc2.com", %{"target" => "vidu.com"})

      assert link_job.credits_charged == 0
      assert main_credits(user) == 10
    end

    test "free features run even without a main wallet" do
      {:ok, user} =
        %User{}
        |> User.telegram_changeset(%{
          telegram_id: System.unique_integer([:positive]),
          telegram_username: "u",
          telegram_first_name: "U",
          username: "nowallet#{System.unique_integer([:positive])}",
          role: :user
        })
        |> Repo.insert()

      assert {:ok, job} = Seo.start_batch(user, :url_status, "a.com\nb.com")
      assert job.credits_charged == 0
    end
  end

  describe "finalize_job/1" do
    test "tallies item outcomes and refunds only failed URLs" do
      user = user_with_credits(10)
      {:ok, job} = Seo.start_batch(user, :check_index, "a\nb\nc")
      assert main_credits(user) == 7

      [i1, i2, i3] = Seo.list_items(job.id)
      Seo.record_item(i1, :success, %{result: %{"indexed" => true}})
      Seo.record_item(i2, :failed, %{result: %{"error" => "boom"}})
      Seo.record_item(i3, :success, %{result: %{"indexed" => false}})

      job = Seo.finalize_job(Seo.get_job!(job.id))

      assert job.status == :done
      assert job.done == 3
      assert job.success_count == 2
      assert job.failed_count == 1
      assert job.credits_refunded == 1
      assert job.completed_at
      # 7 left after reserve + 1 refunded failed URL = 8.
      assert main_credits(user) == 8
    end
  end

  describe "history queries" do
    test "list_recent_jobs + usage_summary aggregate per feature" do
      user = user_with_credits(20)
      {:ok, job} = Seo.start_batch(user, :check_index, "a\nb\nc")
      [i1, i2, i3] = Seo.list_items(job.id)
      Seo.record_item(i1, :success, %{result: %{}})
      Seo.record_item(i2, :success, %{result: %{}})
      Seo.record_item(i3, :failed, %{result: %{}})
      Seo.finalize_job(Seo.get_job!(job.id))

      assert [recent] = Seo.list_recent_jobs(user.id)
      assert recent.id == job.id

      summary = Seo.usage_summary(user.id)
      assert summary[:check_index].jobs == 1
      assert summary[:check_index].urls == 3
      assert summary[:check_index].success == 2
      assert summary[:check_index].failed == 1
    end
  end

  describe "recover_orphaned_jobs/0" do
    test "cancels still-running jobs and refunds their unfinished URLs" do
      user = user_with_credits(10)
      {:ok, job} = Seo.start_batch(user, :check_index, "a\nb\nc\nd")
      assert main_credits(user) == 6

      # Two URLs finished before the (simulated) crash; two never ran.
      [i1, i2, _i3, _i4] = Seo.list_items(job.id)
      Seo.record_item(i1, :success, %{result: %{}})
      Seo.record_item(i2, :failed, %{result: %{}})

      :ok = Seo.recover_orphaned_jobs()

      job = Seo.get_job!(job.id)
      assert job.status == :canceled
      # The 2 unfinished URLs are refunded: 6 + 2 = 8.
      assert main_credits(user) == 8
    end
  end
end
