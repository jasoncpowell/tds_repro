defmodule TdsRepro.KnownLimitationsTest do
  # Writes and filters that fail on released ecto_sql and still fail with the
  # fix. Each test asserts the SQL Server error, so it passes on both, and a
  # change in behaviour shows up as a failure.
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

  # Other field types over existing all_types columns that refuse a varbinary
  # NULL. The adapter doesn't tag their nil, so they fail like :string on text.
  defmodule OtherTypes do
    use Ecto.Schema

    schema "all_types" do
      field :string_text, :map
      field :string_ntext, Tds.Ecto.VarChar
      field :float_float, :decimal
      field :float_real, :decimal
    end
  end

  describe "other field types on columns that refuse a varbinary NULL (not covered by the fix)" do
    for {field, type, column} <- [
          {:string_text, :map, "text"},
          {:string_ntext, Tds.Ecto.VarChar, "ntext"},
          {:float_float, :decimal, "float"},
          {:float_real, :decimal, "real"}
        ] do
      @field field

      test "Repo.update_all/3 can't set a #{inspect(type)} field on a #{column} column to nil",
           %{row: row} do
        query = from(r in OtherTypes, where: r.id == ^row.id)
        assert_refused(206, fn -> Repo.update_all(query, set: [{@field, nil}]) end)
      end
    end
  end

  # Ecto dumps the list for in ^list element by element and leaves a nil
  # element bare, so it reaches the driver untyped and is compared as
  # varbinary.
  describe "a nil inside in ^list (not covered by the fix)" do
    test "Repo.all/2 can't filter a date field on a list with a nil element" do
      values = [nil, ~D[2026-01-01]]
      query = from(r in AllTypes, where: r.date_date in ^values)
      assert_refused(402, fn -> Repo.all(query) end)
    end
  end

  # The fix leaves custom types alone because Ecto never calls their dump/1 for
  # nil: a NULL typed from the primitive would be wrong for a type that stores
  # its values as something else, as TdsRepro.IntDate does.
  describe "a NULL declared as date is refused by an int column" do
    test "raw SQL with a date-typed nil parameter", %{row: row} do
      params = [
        %Tds.Parameter{name: "@1", value: nil, type: :date},
        %Tds.Parameter{name: "@2", value: row.id, type: :integer}
      ]

      assert_refused(206, fn ->
        Repo.query("UPDATE all_types SET int_date_int = @1 WHERE id = @2", params)
      end)
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
