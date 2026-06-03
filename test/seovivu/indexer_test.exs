defmodule Seovivu.IndexerTest do
  use Seovivu.DataCase, async: true

  alias Seovivu.{Accounts, Billing, Indexer}
  alias Seovivu.Accounts.User

  defp user_with_index_credits(credits) do
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
    {:ok, _} = Billing.admin_adjust(Billing.get_wallet(user.id, :index), credits)
    Accounts.get_user!(user.id)
  end

  defp index_credits(user), do: Billing.get_wallet(user.id, :index).credits

  describe "create_project/3" do
    test "reserves index credits and persists the project + urls" do
      user = user_with_index_credits(10)

      {:ok, project} = Indexer.create_project(user, "Dự án A", "a.com\nb.com\nc.com")

      assert project.name == "Dự án A"
      assert project.url_count == 3
      assert project.status == :submitted
      assert index_credits(user) == 7
      assert length(Indexer.list_project_urls(project.id)) == 3
    end

    test "draws from the index wallet, not the main wallet" do
      user = user_with_index_credits(10)
      main_before = Billing.get_wallet(user.id, :main).credits

      {:ok, _} = Indexer.create_project(user, "P", "a.com\nb.com")

      assert Billing.get_wallet(user.id, :main).credits == main_before
      assert index_credits(user) == 8
    end

    test "rejects a blank name / empty urls / insufficient credits" do
      user = user_with_index_credits(1)
      assert {:error, :no_name} = Indexer.create_project(user, "   ", "a.com")
      assert {:error, :no_urls} = Indexer.create_project(user, "P", "  \n ")
      assert {:error, :insufficient_credits} = Indexer.create_project(user, "P", "a\nb\nc")
      assert index_credits(user) == 1
    end
  end

  describe "admin operations" do
    setup do
      user = user_with_index_credits(50)
      {:ok, p1} = Indexer.create_project(user, "P1", "a.com\nb.com")
      {:ok, p2} = Indexer.create_project(user, "P2", "c.com")
      %{user: user, p1: p1, p2: p2}
    end

    test "set_status + toggle_manually_processed", %{p1: p1} do
      {:ok, p1} = Indexer.set_status(p1, :processing)
      assert p1.status == :processing

      {:ok, p1} = Indexer.toggle_manually_processed(p1)
      assert p1.manually_processed
    end

    test "bulk_set_status updates many at once", %{p1: p1, p2: p2} do
      assert 2 = Indexer.bulk_set_status([p1.id, p2.id], :done)
      assert Indexer.get_project!(p1.id).status == :done
      assert Indexer.get_project!(p2.id).status == :done
    end

    test "list_projects_admin filters by status", %{p1: p1} do
      {:ok, _} = Indexer.set_status(p1, :done)
      done = Indexer.list_projects_admin(status: :done)
      assert Enum.map(done, & &1.id) == [p1.id]
    end

    test "delete_projects removes them", %{p1: p1, p2: p2} do
      assert 2 = Indexer.delete_projects([p1.id, p2.id])
      assert Indexer.list_projects_admin() == []
    end

    test "stats aggregates projects/urls/by-status" do
      stats = Indexer.stats()
      assert stats.projects == 2
      assert stats.urls == 3
      assert stats.by_status[:submitted] == 2
    end
  end
end
