import Config

config :tds_repro, ecto_repos: [TdsRepro.Repo]

config :tds_repro, TdsRepro.Repo,
  username: "sa",
  password: "some!Password",
  hostname: "localhost",
  port: 1433,
  database: "tds_repro",
  pool_size: 5

config :logger, level: :info
