val push_action :
     bot_info:Bot_components.Bot_info.t
  -> repo_config_table:(string, Repo_config.t) Base.Hashtbl.t
  -> owner:string
  -> repo:string
  -> base_ref:string
  -> commits_msg:string list
  -> unit Lwt.t
