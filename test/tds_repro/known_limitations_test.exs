defmodule TdsRepro.KnownLimitationsTest do
  # Writes that fail on released ecto_sql and still fail with the fix. Each
  # test asserts the SQL Server error, so it passes on both, and a change in
  # behaviour shows up as a failure.
  use ExUnit.Case

  import Ecto.Changeset
  import Ecto.Query

  alias TdsRepro.{AllTypes, Repo}

  setup do
    Repo.delete_all(AllTypes)

    %{
      row: Repo.insert!(%AllTypes{date_date: ~D[2026-01-01], string_text: "a", string_ntext: "a"})
    }
  end

  describe ":string fields on legacy text columns (not covered by the fix)" do
    for field <- [:string_text, :string_ntext] do
      @field field

      test "Repo.update/2 can't set #{field} to nil", %{row: row} do
        assert_refused(206, fn -> row |> change(%{@field => nil}) |> Repo.update() end)
      end

      test "Repo.insert_all/3 can't insert nil for #{field}" do
        assert_refused(206, fn -> Repo.insert_all(AllTypes, [%{@field => nil}]) end)
      end

      test "Repo.update_all/3 can't set #{field} to nil", %{row: row} do
        query = from(r in AllTypes, where: r.id == ^row.id)
        assert_refused(206, fn -> Repo.update_all(query, set: [{@field, nil}]) end)
      end
    end
  end

  describe "values with no Ecto type, so the adapter has nothing to go on" do
    test "insert_all into a table name instead of a schema" do
      assert_refused(257, fn -> Repo.insert_all("all_types", [%{date_date: nil}]) end)
    end

    test "update_all on a table name instead of a schema", %{row: row} do
      query = from(r in "all_types", where: r.id == ^row.id)
      assert_refused(257, fn -> Repo.update_all(query, set: [date_date: nil]) end)
    end

    test "fragment with a nil parameter", %{row: row} do
      value = nil

      query =
        from(r in AllTypes,
          where: r.id == ^row.id,
          update: [set: [date_date: fragment("?", ^value)]]
        )

      assert_refused(257, fn -> Repo.update_all(query, []) end)
    end

    test "raw SQL with a nil parameter", %{row: row} do
      assert_refused(257, fn ->
        Repo.query("UPDATE all_types SET date_date = @1 WHERE id = @2", [nil, row.id])
      end)
    end
  end

  defp assert_refused(number, fun) do
    error =
      try do
        fun.()
      rescue
        error in Tds.Error -> error
      else
        {:error, %Tds.Error{} = error} -> error
        other -> flunk("expected SQL Server error #{number}, got: #{inspect(other)}")
      end

    assert error.mssql.number == number
  end
end
