defmodule Mosgortrans.Cache do
  use GenServer

  require Logger

  @name :mgt_cache
  @expire 360

  def init(_) do
    {:ok, %{}}
  end

  def start_link() do
    GenServer.start_link(
      __MODULE__,
      nil,
      name: @name
    )
  end

  def fetch(key, fun) do
    GenServer.call(@name, {:fetch, key, fun})
  end

  def handle_call({:fetch, key, fun}, _from, state) do
    now = :os.system_time(:seconds)

    case state[key] do
      {time, val} when now-time<@expire ->
        {:reply, val, state}

      _other ->
        val = fun.()
        {:reply, val, Map.put(state, key, {now, val})}
    end
  end

end
