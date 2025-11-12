val resolve_repo_config :
     bot_info:Bot_components.Bot_info.t
  -> explicit_config:Repo_config.t
  -> Repo_config.t Lwt.t
