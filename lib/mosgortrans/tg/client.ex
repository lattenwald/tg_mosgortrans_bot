defmodule Mosgortrans.Tg.Client do

  use Tesla

  require Logger

  @api_base "https://api.telegram.org/bot"

  adapter Tesla.Adapter.Hackney

  alias Mosgortrans.Util

  def client(token) do
    Tesla.build_client [
      {Tesla.Middleware.BaseUrl, "#{@api_base}#{token}"},
      {Tesla.Middleware.Logger, nil},
      {Tesla.Middleware.EncodeJson, nil},
    ]
    |> IO.inspect
  end

  def setup() do
    IO.inspect(Application.get_all_env(:mosgortrans))
    host = Application.get_env(:mosgortrans, :host)
    endpoint = Application.get_env(:mosgortrans, :endpoint)
    url = "#{host}/#{endpoint}"
    Logger.info("Setting webhook endpoint to #{url}")
    %Tesla.Env{status: 200} = setWebhook(url)
    :ok
  end

  defp client() do
    Application.get_env(:mosgortrans, :token)
    |> IO.inspect()
    |> client()
  end

  def setWebHook(c, url) do
    Logger.debug("client: #{inspect c}")
    post(c, "setWebhook", %{"url" => url})
  end

  def setWebhook(url), do: setWebHook(client(), url)

  def deleteWebhook(c) do
    post(c, "deleteWebhook", %{})
  end

  def deleteWebhook(), do: deleteWebhook(client())

  def getWebhookInfo(c) do
    post(c, "getWebhookInfo", %{})
  end

  def getWebhookInfo(), do: getWebhookInfo(client())

  def send_message(chat_id, text, buttons) do
    %Tesla.Env{status: 200} = send_message(client(), chat_id, text, buttons)
  end

  def send_message(c, chat_id, text, buttons) do
    msg = %{
      "chat_id" => chat_id,
      "text" => text,
      "reply_markup" => keyboard(buttons)
    }
    post(c, "sendMessage", msg)
  end

  def send_callback_reply(query_id) do
    %Tesla.Env{status: 200} = send_callback_reply(client(), query_id)
  end

  def send_callback_reply(c, query_id) do
    reply = %{
      "callback_query_id" => query_id
    }
    post(c, "answerCallbackQuery", reply)
  end

  defp keyboard([]), do: %{"remove_keyboard" => true}
  defp keyboard(buttons = [b|_]) when is_list(b) do
    kbuttons =
      buttons
      |> Enum.map(fn row -> Enum.map(row, fn {title, data} -> %{"text" => title, "callback_data" => data} end) end)
    %{"inline_keyboard" => kbuttons}
  end
  defp keyboard(buttons) do
    keyboard(Util.group(buttons, 5))
  end

end
