defmodule Mosgortrans.Application do
  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    Mosgortrans.Tg.Client.setup()

    children = [
      worker(Mosgortrans.Cache, []),
      worker(Mosgortrans.Tg.Handler, [])
    ]

    opts = [strategy: :one_for_one, name: Mosgortrans.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
