defmodule Cadet.Achievments.GoalTest do
  alias Cadet.Incentives.Goal

  use Cadet.ChangesetCase, entity: Goal

  describe "Changesets" do
    test "valid params" do
      achievement = insert(:achievement, id: 0)

      assert_changeset_db(
        %{
          order: 0,
          text: "Sample Text",
          target: 0,
          achievement_id: achievement.id
        },
        :valid
      )
    end
  end
end
