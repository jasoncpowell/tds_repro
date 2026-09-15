defmodule TdsRepro.WorkaroundsTest do
  # Ways to write nil on released ecto_sql, as described in docs/workarounds.md.
  # Untagged tests pass with or without the fix.
  use ExUnit.Case

  import Ecto.Query

  alias TdsRepro.{AllTypes, Repo}

  setup do
    Repo.delete_all(AllTypes)
    %{row: Repo.insert!(%AllTypes{date_date: ~D[2026-01-01], float_float: 1.5})}
  end

  describe "update_all with a type/2 hint" do
    test "sets a date column to nil", %{row: row} do
      value = nil

      query =
        from(r in AllTypes,
          where: r.id == ^row.id,
          update: [set: [date_date: type(^value, :date)]]
        )

      assert {1, _} = Repo.update_all(query, [])
      assert Repo.get!(AllTypes, row.id).date_date == nil
    end

    test "works on a table name without a schema", %{row: row} do
      value = nil

      query =
        from(r in "all_types",
          where: r.id == ^row.id,
          update: [set: [date_date: type(^value, :date)]]
        )

      assert {1, _} = Repo.update_all(query, [])
    end

    # The hint becomes CAST(@1 AS float), and SQL Server doesn't allow casting
    # varbinary to float at all (error 529), so this only works with the fix.
    @tag :bug
    test "sets a float column to nil", %{row: row} do
      value = nil

      query =
        from(r in AllTypes,
          where: r.id == ^row.id,
          update: [set: [float_float: type(^value, :float)]]
        )

      assert {1, _} = Repo.update_all(query, [])
    end
  end

  describe "raw SQL" do
    test "an explicitly typed %Tds.Parameter{} sets a date column to nil", %{row: row} do
      params = [
        %Tds.Parameter{name: "@1", value: nil, type: :date},
        %Tds.Parameter{name: "@2", value: row.id, type: :integer}
      ]

      assert {:ok, %{num_rows: 1}} =
               Repo.query("UPDATE all_types SET date_date = @1 WHERE id = @2", params)
    end
  end

  describe "insert_all" do
    test "leaving the nil key out inserts NULL" do
      assert {1, _} = Repo.insert_all(AllTypes, [%{float_float: 2.5}])

      assert Repo.one!(from(r in AllTypes, where: r.float_float == 2.5, select: r.date_date)) ==
               nil
    end

    test "rows can leave out different keys" do
      rows = [%{date_date: ~D[2026-02-01]}, %{float_float: 2.5}]
      assert {2, _} = Repo.insert_all(AllTypes, rows)
    end
  end
end
