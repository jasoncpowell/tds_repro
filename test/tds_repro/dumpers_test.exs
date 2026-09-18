defmodule TdsRepro.DumpersTest do
  # Runs values through the adapter's dumpers the way Ecto does before a query
  # is sent, and through the connection's parameter preparation, so these
  # tests need no database. This is the shape of unit test the upstream PR
  # needs.
  use ExUnit.Case, async: true

  alias Ecto.Adapters.Tds.Connection

  @adapter Ecto.Adapters.Tds

  # {Ecto type, type the connection declares the NULL as}
  @typed_nils [
    date: :date,
    time: :time,
    time_usec: :time,
    naive_datetime: :datetime2,
    naive_datetime_usec: :datetime2,
    utc_datetime: :datetimeoffset,
    utc_datetime_usec: :datetimeoffset,
    float: :float
  ]

  describe "nil for types SQL Server won't accept as varbinary" do
    for {ecto_type, tds_type} <- @typed_nils do
      @tag :bug
      test "the adapter tags a #{inspect(ecto_type)} nil with its Ecto type" do
        assert {:ok, {nil, unquote(ecto_type)}} =
                 Ecto.Type.adapter_dump(@adapter, unquote(ecto_type), nil)
      end

      @tag :bug
      test "the connection sends a tagged #{inspect(ecto_type)} nil as a #{inspect(tds_type)} parameter" do
        assert [%Tds.Parameter{name: "@1", value: nil, type: unquote(tds_type)}] =
                 Connection.prepare_params([{nil, unquote(ecto_type)}])
      end
    end

    @tag :bug
    test "a tagged nil is numbered like any other parameter" do
      assert [%{name: "@1"}, %Tds.Parameter{name: "@2", value: nil, type: :date}, %{name: "@3"}] =
               Connection.prepare_params([1, {nil, :date}, "a"])
    end
  end

  describe "other types are unchanged" do
    for ecto_type <- [:integer, :id, :boolean, :decimal, :string, :binary, :binary_id, :map] do
      test "#{inspect(ecto_type)} still dumps nil as nil" do
        assert {:ok, nil} = Ecto.Type.adapter_dump(@adapter, unquote(ecto_type), nil)
      end
    end

    test "non-nil values are not tagged" do
      assert {:ok, ~D[2026-01-01]} = Ecto.Type.adapter_dump(@adapter, :date, ~D[2026-01-01])
      assert {:ok, 1.5} = Ecto.Type.adapter_dump(@adapter, :float, 1.5)
    end

    test "nil inside a list is left to the array dumper, which skips it" do
      assert {:ok, [nil, ~D[2026-01-01]]} =
               Ecto.Type.adapter_dump(@adapter, {:array, :date}, [nil, ~D[2026-01-01]])
    end

    # Ecto never calls a custom type's dump/1 for nil, so the adapter can't
    # know that this type stores its non-nil values as integers.
    test "a custom type with the :date primitive still dumps nil as nil" do
      assert Ecto.Type.type(TdsRepro.IntDate) == :date

      assert {:ok, 20_260_101} =
               Ecto.Type.adapter_dump(@adapter, TdsRepro.IntDate, ~D[2026-01-01])

      assert {:ok, nil} = Ecto.Type.adapter_dump(@adapter, TdsRepro.IntDate, nil)
    end

    test "a parameterized type still dumps nil as nil" do
      type = Ecto.ParameterizedType.init(Ecto.Enum, values: [:a, :b])
      assert {:ok, nil} = Ecto.Type.adapter_dump(@adapter, type, nil)
    end

    test "an untagged nil, as raw SQL sends one, is still left to the driver" do
      assert [%Tds.Parameter{name: "@1", value: nil, type: nil}] =
               Connection.prepare_params([nil])
    end
  end
end
