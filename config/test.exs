import Config

# Tests get their own database so they never touch the repro's data.
config :tds_repro, TdsRepro.Repo, database: "tds_repro_test"
