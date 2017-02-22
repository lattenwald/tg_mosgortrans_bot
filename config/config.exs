use Mix.Config


config :mosgortrans,
  token: "bot token",
  host: "https://my-host.tld",
  endpoint: "telegram bot endpoint"

################# to here ####################
#  Create file "prod.exs" in this directory
# with content just like in this file
# (lines 3-8 only) and set configuration
# stuff according to your bot configuration

try do
  import_config "#{Mix.env}.exs"
catch
  _, _ -> :missing
end
