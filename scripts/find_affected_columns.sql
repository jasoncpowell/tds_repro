-- Nullable columns that can hit the Ecto/Tds nil parameter bug.
--
-- On released ecto_sql, writing nil through Ecto sends a NULL parameter with
-- no type, which the tds driver declares as varbinary. SQL Server refuses to
-- convert varbinary to the column types below, so the write fails with error
-- 257 or 206.
--
-- A listed column is only affected if an app writes nil to it through Ecto
-- (Repo.update, Repo.insert_all, Repo.update_all, ...). Whether the fix covers
-- it depends on the Ecto field type mapped to the column; see `note`.
--
-- Run it in any SQL Server client against the database you want to check, or
-- against this repo's database with: mix run scripts/find_affected_columns.exs

SELECT
  c.TABLE_SCHEMA AS table_schema,
  c.TABLE_NAME AS table_name,
  c.COLUMN_NAME AS column_name,
  c.DATA_TYPE AS data_type,
  CASE
    WHEN c.DATA_TYPE IN ('text', 'ntext') THEN 'legacy type, not covered by the fix'
    WHEN c.DATA_TYPE IN ('float', 'real') THEN 'covered when the Ecto field is :float'
    ELSE 'covered when the Ecto field is the matching date/time type'
  END AS note
FROM INFORMATION_SCHEMA.COLUMNS AS c
JOIN INFORMATION_SCHEMA.TABLES AS t
  ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME
WHERE t.TABLE_TYPE = 'BASE TABLE'
  AND c.IS_NULLABLE = 'YES'
  AND c.DATA_TYPE IN ('date', 'time', 'datetime2', 'datetimeoffset', 'float', 'real', 'text', 'ntext')
ORDER BY c.TABLE_SCHEMA, c.TABLE_NAME, c.ORDINAL_POSITION;
