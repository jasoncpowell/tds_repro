defmodule TdsRepro.Repo.Migrations.CreateAllTypes do
  use Ecto.Migration

  # Raw SQL, because the column types are the point and several of them are
  # legacy types Ecto's migrations never create. Must match TdsRepro.AllTypes.
  def up do
    execute """
    CREATE TABLE all_types (
      id bigint IDENTITY(1, 1) PRIMARY KEY,
      integer_int int NULL,
      id_bigint bigint NULL,
      boolean_bit bit NULL,
      decimal_decimal decimal(10, 2) NULL,
      string_nvarchar nvarchar(255) NULL,
      string_nvarchar_max nvarchar(max) NULL,
      binary_varbinary varbinary(max) NULL,
      binary_id_uniqueidentifier uniqueidentifier NULL,
      map_nvarchar_max nvarchar(max) NULL,
      float_float float NULL,
      date_date date NULL,
      time_time time(0) NULL,
      time_usec_time time(6) NULL,
      naive_datetime_datetime datetime NULL,
      naive_datetime_usec_datetime2 datetime2(6) NULL,
      utc_datetime_datetime datetime NULL,
      utc_datetime_usec_datetime2 datetime2(6) NULL,
      decimal_money money NULL,
      string_varchar varchar(255) NULL,
      string_text text NULL,
      string_ntext ntext NULL,
      binary_image image NULL,
      float_real real NULL,
      naive_datetime_smalldatetime smalldatetime NULL,
      utc_datetime_usec_datetimeoffset datetimeoffset NULL,
      metadata nvarchar(max) NULL
    )
    """
  end

  def down do
    execute "DROP TABLE all_types"
  end
end
