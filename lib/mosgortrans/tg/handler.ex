defmodule Mosgortrans.Tg.Handler do

  use Plug.Router

  require Logger

  alias Mosgortrans.{Client, Util}

  @max_routes 80

  # plug Logger
  plug Plug.Parsers, parsers: [:json], json_decoder: Poison
  plug :match
  plug :dispatch

  def start_link() do
    {:ok, _} = Plug.Adapters.Cowboy.http(
      __MODULE__,
      nil,
      port: Application.get_env(:mosgortrans, :port, 8234)
    )
  end

  get "/" do
    Logger.debug("ok")
    conn |> respond
  end

  post _ do
    endpoint = "/" <> Application.get_env(:mosgortrans, :endpoint)

    Logger.debug("path #{conn.request_path}")

    case conn.request_path do
      ^endpoint ->
        conn
        |> Plug.Conn.fetch_query_params
        |> extract_chat_id
        |> query
        |> respond

      other ->
        Logger.info "endpoint #{inspect other} is not supported"
        Plug.Conn.send_resp(conn, 404, "oops")
    end
  end

  match _, do: Plug.Conn.send_resp(conn, 404, "oops")

  defp extract_chat_id(
    conn = %{body_params: %{"message" => %{"chat" => %{"id" => chat_id}}}}
  ) do
    conn
    |> Plug.Conn.assign(:chat_id, chat_id)
  end

  defp extract_chat_id(
    conn = %{body_params: %{"callback_query" => %{"message" => %{"chat" => %{"id" => chat_id}}}}}
  ) do
    conn
    |> Plug.Conn.assign(:chat_id, chat_id)
  end

  defp query(
    conn = %{body_params: %{"callback_query" => query}}
  ) do
    conn
    |> Plug.Conn.assign(:callback_query, query)
    |> callback_query
  end

  defp query(
    conn = %{body_params: %{"message" => %{"text" => text}}}
  ) do
    conn
    |> Plug.Conn.assign(:message, text)
    |> incoming_message
  end

  defp incoming_message(conn) do
    text = conn.assigns.message
    {reply, buttons} =
      case text do
        "?" -> cmd_init()
      end
    send_message(conn.assigns.chat_id, reply, buttons)
    conn
  end

  defp callback_query(conn) do
    query = conn.assigns.callback_query
    {reply, buttons} =
      case query["data"] do
        "bus" <> rest -> cmd_routes(:bus, rest)
        "trolleybus" <> rest -> cmd_routes(:trolleybus, rest)
        "tram" <> rest -> cmd_routes(:tram, rest)
        "direction " <> route -> cmd_directions(route)
        "stations " <> route -> cmd_stations(route)
        "schedule " <> route -> cmd_schedule(route)
      end
    send_callback_reply(conn.assigns.callback_query["id"])
    send_message(conn.assigns.chat_id, reply, buttons)
    conn
  end

  defp send_message(chat_id, reply, buttons) do
    Mosgortrans.Tg.Client.send_message(chat_id, reply, buttons)
  end

  defp send_callback_reply(query_id) do
    Mosgortrans.Tg.Client.send_callback_reply(query_id)
  end

  defp cmd_init() do
    {
      "Какой транспорт вас интересует?",
      [
        {"автобус", :bus},
        {"троллейбус", :trolleybus},
        {"трамвай", :tram},
      ]
    }
  end

  defp limit_range(routes, ""), do: routes
  defp limit_range(routes, range_str) do
    [[_, from, to]] = Regex.scan(~r{^:::(.*?):::(.*?):::$}, range_str)

    # nice hack, memory is cheap
    routes
    |> Enum.drop_while(fn r -> r != from end)
    |> Enum.reverse
    |> Enum.drop_while(fn r -> r != to end)
    |> Enum.reverse
  end


  defp cmd_routes(type, range_str) do
    Logger.debug "routes for #{inspect type} #{inspect range_str}"
    routes = Client.routes(type) |> limit_range(range_str)

    buttons = if length(routes) > @max_routes do
      Util.group(routes, @max_routes)
      |> Enum.map(fn range ->
        fst = List.first(range)
        lst = List.last(range)
        {"#{fst} - #{lst}", "#{type}:::#{fst}:::#{lst}:::"}
      end)
    else
      Enum.zip(routes, Enum.map(routes, fn r -> "direction #{type} #{r}" end))
    end

    {
      "Выберите номер маршрута",
      buttons
    }
  end

  defp cmd_directions("bus " <> route), do: cmd_directions(:bus, route)
  defp cmd_directions("trolleybus " <> route), do: cmd_directions(:trolleybus, route)
  defp cmd_directions("tram " <> route), do: cmd_directions(:tram, route)
  defp cmd_directions(type, route) do
    directions = Client.directions(type, route, Util.current_days)
    buttons =
      Enum.zip(directions, Enum.map([:ab, :ba], fn dir -> "stations #{type} #{dir} #{route}" end))
      |> Enum.map(fn btn -> [btn] end)

    {
      "Выберите направление",
      buttons
    }
  end

  defp cmd_stations("bus " <> dir_route), do: cmd_stations(:bus, dir_route)
  defp cmd_stations("trolleybus " <> dir_route), do: cmd_stations(:trolleybus, dir_route)
  defp cmd_stations("tram " <> dir_route), do: cmd_stations(:tram, dir_route)
  defp cmd_stations(type, dir_route) do
    [[_, dir_str, route]] = Regex.scan(~r{^(ab|ba) (.*)$}, dir_route)
    dir = Util.string_to_dir(dir_str)
    stations = Client.stations(type, route, Util.current_days, dir)

    buttons = Enum.zip(
      stations,
      Enum.map(
        0 .. length(stations) - 1,
        fn i -> "schedule #{type} #{dir} #{i} #{route}" end
      )
    )

    {
      "Выберите остановку",
      buttons
    }
  end

  defp cmd_schedule("bus " <> dir_route), do: cmd_schedule(:bus, dir_route)
  defp cmd_schedule("trolleybus " <> dir_route), do: cmd_schedule(:trolleybus, dir_route)
  defp cmd_schedule("tram " <> dir_route), do: cmd_schedule(:tram, dir_route)
  defp cmd_schedule(type, dir_route) do
    [[_, dir_str, station_str, route]] =
      Regex.scan(~r{^(ab|ba) (\d+) (.*)$}, dir_route)
    dir = Util.string_to_dir(dir_str)
    station = String.to_integer(station_str)

    schedule = Client.schedule(type, route, Util.current_days, dir, station)

    {
      show_schedule(schedule),
      []
    }
  end

  defp show_schedule(%{times: times}) do
    times
    |> Enum.map(fn {h, m} -> :io_lib.format('~2..0B:~2..0B', [h, m]) |> :erlang.list_to_binary end)
    |> Enum.join("\n")
  end

  defp respond(conn) do
    conn
    |> Plug.Conn.send_resp(200, "")
  end

end
