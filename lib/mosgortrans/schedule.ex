defmodule Mosgortrans.Schedule do
  defstruct [:type, :route, :station_at, :station_from, :station_to, :days, {:times, []}]
end
