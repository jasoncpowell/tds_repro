import Config

config :tds_repro, ecto_repos: [TdsRepro.Repo]

config :tds_repro, TdsRepro.Repo,
  username: "sa",
  password: "some!Password",
  hostname: System.get_env("MSSQL_HOST", "localhost"),
  port: String.to_integer(System.get_env("MSSQL_PORT", "1433")),
  database: "tds_repro",
  pool_size: 5

config :logger, level: :info

if config_env() == :test do
  import_config "test.exs"
end
