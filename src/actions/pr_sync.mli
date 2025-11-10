val run_ci_action :
     bot_info:Bot_components.Bot_info.t
  -> comment_info:Bot_components.GitHub_types.comment_info
  -> ?full_ci:bool
  -> gitlab_mapping:(string, string) Base.Hashtbl.t
  -> github_mapping:(string, string * string) Base.Hashtbl.t
  -> unit
  -> (Cohttp.Response.t * Cohttp_lwt__Body.t) Lwt.t

val pull_request_updated_action :
     bot_info:Bot_components.Bot_info.t
  -> action:Bot_components.GitHub_types.pull_request_action
  -> pr_info:
       Bot_components.GitHub_types.issue_info
       Bot_components.GitHub_types.pull_request_info
  -> gitlab_mapping:(string, string) Base.Hashtbl.t
  -> github_mapping:(string, string * string) Base.Hashtbl.t
  -> (Cohttp.Response.t * Cohttp_lwt__.Body.t) Lwt.t

val rocq_check_needs_rebase_pr :
     bot_info:Bot_components.Bot_info.t
  -> owner:string
  -> repo:string
  -> warn_after:int
  -> close_after:int
  -> throttle:int
  -> unit Lwt.t

val rocq_check_stale_pr :
     bot_info:Bot_components.Bot_info.t
  -> owner:string
  -> repo:string
  -> after:int
  -> throttle:int
  -> unit Lwt.t
