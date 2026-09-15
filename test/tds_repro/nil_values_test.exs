defmodule TdsRepro.NilValuesTest do
  # Writes nil to one column at a time, through each Ecto write path, for every
  # field type / column type combination in TdsRepro.AllTypes.
  #
  # Tests tagged :bug fail on released ecto_sql (ECTO_SQL=upstream) and pass
  # with the fix in vendor/ecto_sql. Untagged tests pass on both.
  use ExUnit.Case

  import Ecto.Changeset
  import Ecto.Query

  alias TdsRepro.{AllTypes, Metadata, Repo}

  # SQL Server refuses a varbinary NULL for these; the fix sends a typed NULL.
  @fixed_by_patch [
    :date_date,
    :time_time,
    :time_usec_time,
    :naive_datetime_usec_datetime2,
    :utc_datetime_usec_datetime2,
    :utc_datetime_usec_datetimeoffset,
    :float_float,
    :float_real
  ]

  # Also refused, but not covered by the fix. See known_limitations_test.exs.
  @not_covered [:string_text, :string_ntext]

  setup do
    Repo.delete_all(AllTypes)

    values =
      Map.new(AllTypes.columns(), fn {field, _type, _column, sample} -> {field, sample} end)

    row =
      AllTypes
      |> struct(values)
      |> Map.put(:metadata, %Metadata{note: "first", reviewed_on: ~D[2026-01-01]})
      |> Repo.insert!()

    %{row: row, values: values}
  end

  for {field, type, column, _sample} <- AllTypes.columns(), field not in @not_covered do
    @field field

    describe "#{inspect(type)} field on a #{column} column" do
      if field in @fixed_by_patch, do: @describetag(:bug)

      test "Repo.update/2 sets it to nil", %{row: row} do
        assert {:ok, _} = row |> change(%{@field => nil}) |> Repo.update()
        assert Repo.get!(AllTypes, row.id) |> Map.fetch!(@field) == nil
      end

      test "Repo.insert_all/3 inserts nil" do
        assert {1, _} = Repo.insert_all(AllTypes, [%{@field => nil}])
      end

      test "Repo.update_all/3 sets it to nil", %{row: row} do
        query = from(r in AllTypes, where: r.id == ^row.id)
        assert {1, _} = Repo.update_all(query, set: [{@field, nil}])
      end
    end
  end

  describe "unaffected behaviour" do
    test "non-nil values write and read back", %{row: row, values: values} do
      loaded = Repo.get!(AllTypes, row.id)

      for {field, expected} <- values do
        actual = Map.fetch!(loaded, field)
        assert same_value?(actual, expected), "#{field}: got #{inspect(actual)}"
      end
    end

    test "a nil date inside an embedded schema is saved as JSON", %{row: row} do
      row
      |> change()
      |> put_embed(:metadata, %Metadata{note: "second", reviewed_on: nil})
      |> Repo.update!()

      assert %Metadata{note: "second", reviewed_on: nil} = Repo.get!(AllTypes, row.id).metadata
    end
  end

  defp same_value?(%Decimal{} = actual, %Decimal{} = expected),
    do: Decimal.equal?(actual, expected)

  defp same_value?(%DateTime{} = actual, %DateTime{} = expected),
    do: DateTime.compare(actual, expected) == :eq

  defp same_value?(actual, expected), do: actual == expected
end
