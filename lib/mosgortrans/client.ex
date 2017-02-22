defmodule Mosgortrans.Client do
  use Tesla

  plug Tesla.Middleware.BaseUrl, "http://www.mosgortrans.org/pass3"
  plug Tesla.Middleware.Logger
  plug Tesla.Middleware.Charset

  adapter Tesla.Adapter.Hackney

  alias Mosgortrans.Util

  @type transport() :: :bus | :trolleybus | :tram
  @type days() :: :weekdays | :weekend
  @type direction() :: :ab | :ba
  @type route() :: String.t()

  @spec days_to_string(days()) :: String.t()
  defp days_to_string(:weekdays), do: "1111100"
  defp days_to_string(:weekend),  do: "0000011"

  @spec dir_to_string(direction()) :: String.t()
  defp dir_to_string(:ab), do: "AB"
  defp dir_to_string(:ba), do: "BA"

  @spec routes(transport()) :: [route()]
  def routes(type_str) do
    type = Util.type_to_string(type_str)
    Mosgortrans.Cache.fetch({:routes, type}, fn -> get_routes(type) end)
  end

  @spec get_routes(String.t()) :: [route()]
  defp get_routes(type) do
    %Tesla.Env{
      status: 200,
      body: body
    } = get("request.ajax.php?list=ways&type=#{type}") |> IO.inspect

    body |> String.split(~r[\n]) |> Enum.filter(fn s -> String.length(s) > 0 end)
  end

  @spec directions(transport(), route(), days()) :: [String.t()]
  def directions(type, route, days) do
    str_type = Util.type_to_string(type)
    str_days = days_to_string(days)
    %Tesla.Env{
      status: 200,
      body: body
    } = get("request.ajax.php?list=directions&type=#{str_type}&way=#{route}&date=#{str_days}")

    body
    |> String.split(~r[\n])
    |> Enum.take(2)
  end

  @spec stations(transport(), route(), days(), direction()) :: [String.t()]
  def stations(type, route, days, direction) do
    str_type = Util.type_to_string(type)
    str_days = days_to_string(days)
    str_dir = dir_to_string(direction)
    %Tesla.Env{
      status: 200,
      body: body
    } = get("request.ajax.php?list=waypoints&type=#{str_type}&way=#{route}&date=#{str_days}&direction=#{str_dir}")

    body
    |> String.split(~r[\n])
    |> Enum.filter(fn s -> String.length(s) > 0 end)
  end

  def schedule(type, route, days, direction, station) do
    str_type = Util.type_to_string(type)
    str_days = days_to_string(days)
    str_dir = dir_to_string(direction)
    %Tesla.Env{
      status: 200,
      body: body
    } = get("shedule.php?type=#{str_type}&way=#{route}&date=#{str_days}&direction=#{str_dir}&waypoint=#{station}")
    body |> parse_schedule
  end

  def parse_mins(str) do

    min_re = ~r{<span class="minutes"\s*>(\d+)</span>}
    Regex.scan(min_re, str)
    |> Enum.map(&tl(&1))
    |> List.flatten
    |> Enum.map(&String.to_integer(&1))
  end

  def parse_schedule(str) do
    alias Mosgortrans.Schedule

    station = Regex.named_captures(~r{<h2>(?<station>.*?)</h2>}, str)["station"]

    route = Regex.named_captures(~r{<h3>Расписание (?<type_str>\S+) маршрута (?<route>\S+) от}, str)

    from_to = Regex.named_captures(~r{от остановки\s*<b>\s*(?<from>.*?) до остановки (?<to>.*?)</}s, str)

    days = Regex.named_captures(~r{<h3>Для дней недели: (?<days>.*?)</}, str)["days"] |> str_to_days

    time_re = ~r{<td.*?>\s*<span class="hour">(\d+)</span></td>\s*<td.*?>(.*?)</td>}s

    times =
      Regex.scan(time_re, str)
      |> Stream.map(&tl(&1))
      |> Stream.map(fn [h, min_str] -> {String.to_integer(h), parse_mins(min_str)} end)
      |> Enum.map(fn {h, mins} -> Enum.map(mins, fn m -> {h, m} end) end)
      |> List.flatten

    %Schedule{
      type: str_to_type(route["type_str"]),
      route: route["route"],
      station_from: from_to["from"],
      station_to: from_to["to"],
      station_at: station,
      times: times,
      days: days,
    }
  end

  defp str_to_type("автобус" <> _), do: :bus
  defp str_to_type("троллейбус" <> _), do: :trolleybus
  defp str_to_type("трамвай" <> _), do: :tram

  defp str_to_days("Понедельник," <> _), do: :weekdays
  defp str_to_days("Суббота," <> _), do: :weekend
end

defmodule Tesla.Middleware.Charset do
  @moduledoc """
  Decode answer from encoding indicated in content-type header to UTF-8
  """

  # TODO: add option: ignore if we or iconv fails to detect charset
  # TODO: add option: charset to convert to (default utf-8)
  # TODO: add UTF8 (no dash) detection

  def call(env, next, _opts) do
    %Tesla.Env{headers: headers, body: body} = new_env = Tesla.run(env, next)
    ctype = headers["content-type"] || ""
    charset = Regex.named_captures(~r{^(?<ctype>.*);\s*charset=(?<charset>[^\s;]+)}, ctype)["charset"] || "utf-8" |> String.downcase

    case charset do
      "utf-8" -> new_env

      other ->
        decoded = :iconv.convert(other, "utf-8", body)

        %Tesla.Env{new_env | body: decoded}
        |> Tesla.Middleware.Headers.call([], %{"content-type" => "#{ctype}; charset=utf-8"})
    end

  end

end

defmodule Tesla.Middleware.Cache do
  @moduledoc """
  Simple caching middleware, ignoring request body
  """

  def call(env, next, _opts) do
    key = {next.method, next.path}
    Mosgortrans.Cache.fetch(key, fn -> Tesla.run(env, next) end)
  end

end
