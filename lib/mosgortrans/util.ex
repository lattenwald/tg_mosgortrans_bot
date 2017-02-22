defmodule Mosgortrans.Util do
  def group(list, count), do: group(list, count, []) |> :lists.reverse

  defp group(list, count, acc) when length(list) <= count do
    [list | acc]
  end
  defp group(list, count, acc) do
    {h, t} = Enum.split(list, count)
    group(t, count, [h | acc])
  end

  # @spec type_to_string(transport()) :: String.t()
  def type_to_string(:bus), do: "avto"
  def type_to_string(:trolleybus), do: "trol"
  def type_to_string(:tram), do: "tram"

  def string_to_dir("ab"), do: :ab
  def string_to_dir("ba"), do: :ba

  def current_days do
    wday = Timex.now |> Timex.weekday
    if wday>0 && wday<6 do
      :weekdays
    else
      :weekend
    end
  end


end
