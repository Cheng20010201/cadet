defmodule Cadet.Incentives.Goals do
  @moduledoc """
  Stores `Goal`s.
  """
  use Cadet, [:context, :display]

  alias Cadet.Incentives.Goal

  alias Cadet.Accounts.User

  import Ecto.Query

  @doc """
  Returns all goals.
  """
  @spec get_goals() :: [%Goal{}]
  def get_goals do
    Repo.all(Goal)
  end

  @doc """
  Returns goals with user progress.
  """
  def get_goals_with_progress(%User{id: user_id}) do
    Goal
    |> join(:left, [g], p in assoc(g, :progress), on: p.user_id == ^user_id)
    |> Repo.all()
  end

  @spec upsert_goal(map()) :: {:ok, %Goal{}} | {:error, {:bad_request, String.t()}}
  @doc """
  Inserts a new goal, or updates it if it already exists.
  """
  def upsert_goal(attrs) do
    case attrs[:uuid] || attrs["uuid"] do
      nil ->
        {:error, {:bad_request, "No UUID specified in Goal"}}

      uuid ->
        Goal
        |> Repo.get(uuid)
        |> (&(&1 || %Goal{})).()
        |> Goal.changeset(attrs)
        |> Repo.insert_or_update()
        |> case do
          result = {:ok, _} ->
            result

          {:error, changeset} ->
            {:error, {:bad_request, full_error_messages(changeset)}}
        end
    end
  end

  @spec upsert_goals([map()]) :: {:ok, nil} | {:error, {:bad_request, String.t()}}
  def upsert_goals(many_attrs) do
    Repo.transaction(fn ->
      for attrs <- many_attrs do
        case upsert_goal(attrs) do
          {:ok, _} -> nil
          {:error, error} -> Repo.rollback(error)
        end
      end

      nil
    end)
  end

  @doc """
  Deletes a goal.
  """
  @spec delete_goal(Ecto.UUID.t()) ::
          :ok | {:error, {:not_found, String.t()}}
  def delete_goal(uuid) when is_binary(uuid) do
    case Goal
         |> where(uuid: ^uuid)
         |> Repo.delete_all() do
      {0, _} -> {:error, {:not_found, "Goal not found"}}
      {_, _} -> :ok
    end
  end
end
