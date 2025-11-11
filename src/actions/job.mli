open Bot_components

val job_action :
     bot_info:Bot_info.t
  -> repo_config_table:(string, Repo_config.t) Base.Hashtbl.t
  -> GitLab_types.ci_common_info GitLab_types.job_info
  -> gitlab_mapping:(string, string) Base.Hashtbl.t
  -> unit Lwt.t
