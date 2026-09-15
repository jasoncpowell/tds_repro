defmodule TdsRepro.DumpersTest do
  # Runs values through the adapter's dumpers the way Ecto does before a query
  # is sent, so these tests need no database. This is the shape of unit test
  # the upstream PR needs.
  use ExUnit.Case, async: true

  @adapter Ecto.Adapters.Tds

  describe "nil for types SQL Server won't accept as varbinary" do
    for {ecto_type, tds_type} <- [
          date: :date,
          time: :time,
          time_usec: :time,
          naive_datetime: :datetime2,
          naive_datetime_usec: :datetime2,
          utc_datetime: :datetimeoffset,
          utc_datetime_usec: :datetimeoffset,
          float: :float
        ] do
      @tag :bug
      test "#{inspect(ecto_type)} dumps as a #{inspect(tds_type)} parameter" do
        assert {:ok, %Tds.Parameter{value: nil, type: unquote(tds_type)}} =
                 Ecto.Type.adapter_dump(@adapter, unquote(ecto_type), nil)
      end
    end
  end

  describe "other types are unchanged" do
    for ecto_type <- [:integer, :id, :boolean, :decimal, :string, :binary, :binary_id, :map] do
      test "#{inspect(ecto_type)} still dumps nil as nil" do
        assert {:ok, nil} = Ecto.Type.adapter_dump(@adapter, unquote(ecto_type), nil)
      end
    end

    test "non-nil values are not wrapped" do
      assert {:ok, ~D[2026-01-01]} = Ecto.Type.adapter_dump(@adapter, :date, ~D[2026-01-01])
      assert {:ok, 1.5} = Ecto.Type.adapter_dump(@adapter, :float, 1.5)
    end
  end
end
