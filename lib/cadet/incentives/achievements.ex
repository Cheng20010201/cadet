defmodule Cadet.Incentives.Achievements do
  @moduledoc """
  Stores `Achievement`s.
  """
  use Cadet, [:context, :display]

  alias Cadet.Incentives.Achievement

  import Ecto.Query

  @doc """
  Returns all achievements.

  This returns Achievement structs with prerequisites and goal association maps pre-loaded.
  """
  @spec get_achievements() :: [%Achievement{}]
  def get_achievements do
    Achievement
    |> preload([:prerequisites, :goals])
    |> Repo.all()
  end

  @spec upsert_achievement(map()) :: {:ok, %Achievement{}} | {:error, {:bad_request, String.t()}}
  @doc """
  Inserts a new achievement, or updates it if it already exists.
  """
  def upsert_achievement(attrs) do
    case attrs[:uuid] || attrs["uuid"] do
      nil ->
        {:error, {:bad_request, "No UUID specified in Achievement"}}

      uuid ->
        Achievement
        |> preload([:prerequisites, :goals])
        |> Repo.get(uuid)
        |> (&(&1 || %Achievement{})).()
        |> Achievement.changeset(attrs)
        |> Repo.insert_or_update()
        |> case do
          result = {:ok, _} ->
            result

          {:error, changeset} ->
            {:error, {:bad_request, full_error_messages(changeset)}}
        end
    end
  end

  @spec upsert_achievements([map()]) :: {:ok, nil} | {:error, {:bad_request, String.t()}}
  def upsert_achievements(many_attrs) do
    Repo.transaction(fn ->
      for attrs <- many_attrs do
        case upsert_achievement(attrs) do
          {:ok, _} -> nil
          {:error, error} -> Repo.rollback(error)
        end
      end

      nil
    end)
  end

  @doc """
  Deletes an achievement.
  """
  @spec delete_achievement(Ecto.UUID.t()) ::
          :ok | {:error, {:not_found, String.t()}}
  def delete_achievement(uuid) when is_binary(uuid) do
    case Achievement
         |> where(uuid: ^uuid)
         |> Repo.delete_all() do
      {0, _} -> {:error, {:not_found, "Achievement not found"}}
      {_, _} -> :ok
    end
  end
end
