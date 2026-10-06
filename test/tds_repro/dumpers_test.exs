defmodule TdsRepro.DumpersTest do
  # Runs values through the adapter's dumpers the way Ecto does before a query
  # is sent, and through the connection's parameter preparation, so these
  # tests need no database. This is the shape of unit test the upstream PR
  # needs.
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Ecto.Adapters.Tds.Connection
  alias TdsRepro.{AllTypes, Repo}

  @adapter Ecto.Adapters.Tds

  # {Ecto type, TDS type the adapter tags its nil with}
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

  # A non-nil value of each type in @typed_nils. The _usec types need
  # microsecond precision, the others none, or Ecto refuses to dump them.
  @values [
    date: ~D[2026-01-01],
    time: ~T[09:30:00],
    time_usec: ~T[09:30:00.123456],
    naive_datetime: ~N[2026-01-01 09:30:00],
    naive_datetime_usec: ~N[2026-01-01 09:30:00.123456],
    utc_datetime: ~U[2026-01-01 09:30:00Z],
    utc_datetime_usec: ~U[2026-01-01 09:30:00.123456Z],
    float: 1.5
  ]

  describe "nil for types SQL Server won't accept as varbinary" do
    for {ecto_type, tds_type} <- @typed_nils do
      @tag :bug
      test "the adapter tags a #{inspect(ecto_type)} nil with #{inspect(tds_type)}" do
        assert {:ok, {nil, unquote(tds_type)}} =
                 Ecto.Type.adapter_dump(@adapter, unquote(ecto_type), nil)
      end
    end

    for tds_type <- @typed_nils |> Keyword.values() |> Enum.uniq() do
      @tag :bug
      test "the connection sends {nil, #{inspect(tds_type)}} as a #{inspect(tds_type)} parameter" do
        assert [%Tds.Parameter{name: "@1", value: nil, type: unquote(tds_type)}] =
                 Connection.prepare_params([{nil, unquote(tds_type)}])
      end
    end

    @tag :bug
    test "a tagged nil is numbered like any other parameter" do
      assert [%{name: "@1"}, %Tds.Parameter{name: "@2", value: nil, type: :date}, %{name: "@3"}] =
               Connection.prepare_params([1, {nil, :date}, "a"])
    end
  end

  describe "a nil gets the parameter type of a value of its field" do
    # Three places decide these types: the adapter's dumpers for a nil, the
    # connection's prepare_param/1 for a date or time value, and the driver's
    # Tds.Parameter.fix_data_type/1 for a float, which the connection leaves
    # untyped. Comparing what reaches the driver keeps them in step.
    defp parameter_type(type, value) do
      {:ok, dumped} = Ecto.Type.adapter_dump(@adapter, type, value)
      [param] = Connection.prepare_params([dumped])
      Tds.Parameter.fix_data_type(param).type
    end

    for {type, _value} <- @values do
      @tag :bug
      test "a #{inspect(type)} nil gets the parameter type of a value" do
        type = unquote(type)
        assert parameter_type(type, nil) == parameter_type(type, Keyword.fetch!(@values, type))
      end
    end
  end

  describe "what to_sql/3 shows" do
    # The params are the dumped values, so a nil shows its tag. to_sql/3 needs
    # the running Repo but sends nothing to SQL Server.
    @tag :bug
    test "a nil parameter carries the TDS type it is declared as" do
      value = nil
      query = from(r in AllTypes, update: [set: [utc_datetime_usec_datetimeoffset: ^value]])

      assert {_sql, [{nil, :datetimeoffset}]} = Repo.to_sql(:update_all, query)
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

  describe "a nil filter is still compared with IS NULL" do
    # Repo.update/2 and Repo.delete/2 dump changeset.filters through the
    # adapter and hand the dumped values to Connection.update/5 and
    # Connection.delete/4, which render a nil filter as IS NULL. A tagged nil
    # has to reach the same clause: comparing a column with a NULL parameter is
    # never true, so the row would not match and Ecto would raise
    # Ecto.StaleEntryError. These assert the SQL, not the tag, so they hold on
    # released ecto_sql and with the fix alike.
    defp dump!(type, value) do
      {:ok, dumped} = Ecto.Type.adapter_dump(@adapter, type, value)
      dumped
    end

    for {ecto_type, _tds_type} <- @typed_nils do
      test "UPDATE filters on a nil #{inspect(ecto_type)} with IS NULL" do
        filters = [{:id, 1}, {:cleared, dump!(unquote(ecto_type), nil)}]

        assert IO.iodata_to_binary(Connection.update(nil, "t", [:x], filters, [])) ==
                 "UPDATE [t] SET [x] = @1 WHERE [id] = @2 AND [cleared] IS NULL"
      end

      test "DELETE filters on a nil #{inspect(ecto_type)} with IS NULL" do
        filters = [{:id, 1}, {:cleared, dump!(unquote(ecto_type), nil)}]

        assert IO.iodata_to_binary(Connection.delete(nil, "t", filters, [])) ==
                 "DELETE FROM [t] WHERE [id] = @1 AND [cleared] IS NULL"
      end
    end

    test "a non-nil filter is still compared with a parameter" do
      filters = [{:id, 1}, {:due_on, dump!(:date, ~D[2026-01-01])}]

      assert IO.iodata_to_binary(Connection.update(nil, "t", [:x], filters, [])) ==
               "UPDATE [t] SET [x] = @1 WHERE [id] = @2 AND [due_on] = @3"
    end
  end
end
