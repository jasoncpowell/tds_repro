defmodule TdsRepro.Repo do
  use Ecto.Repo,
    otp_app: :tds_repro,
    adapter: Ecto.Adapters.Tds
end
