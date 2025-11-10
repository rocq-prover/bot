type build_failure = Warn of string | Retry of string | Ignore of string

val send_status_check :
     bot_info:Bot_components.Bot_info.t
  -> Bot_components.GitLab_types.ci_common_info
     Bot_components.GitLab_types.job_info
  -> pr_num:int option
  -> string * string
  -> github_repo_full_name:string
  -> gitlab_domain:string
  -> gitlab_repo_full_name:string
  -> context:string
  -> failure_reason:string
  -> external_id:string
  -> trace:string
  -> ?summary_builder:(string list -> string -> string Lwt.t)
  -> ?allow_failure_handler:
       (   bot_info:Bot_components.Bot_info.t
        -> job_name:string
        -> job_url:string
        -> pr_num:int option
        -> head_commit:string
        -> string * string
        -> gitlab_repo_full_name:string
        -> unit Lwt.t )
  -> unit
  -> unit Lwt.t

val trace_action : repo_full_name:string -> string -> build_failure Lwt.t

val job_failure :
     bot_info:Bot_components.Bot_info.t
  -> Bot_components.GitLab_types.ci_common_info
     Bot_components.GitLab_types.job_info
  -> pr_num:int option
  -> string * string
  -> github_repo_full_name:string
  -> gitlab_domain:string
  -> gitlab_repo_full_name:string
  -> context:string
  -> failure_reason:string
  -> external_id:string
  -> ?summary_builder:(string list -> string -> string Lwt.t)
  -> ?allow_failure_handler:
       (   bot_info:Bot_components.Bot_info.t
        -> job_name:string
        -> job_url:string
        -> pr_num:int option
        -> head_commit:string
        -> string * string
        -> gitlab_repo_full_name:string
        -> unit Lwt.t )
  -> unit
  -> unit Lwt.t

val job_success_or_pending :
     bot_info:Bot_components.Bot_info.t
  -> string * string
  -> Bot_components.GitLab_types.ci_common_info
     Bot_components.GitLab_types.job_info
  -> github_repo_full_name:string
  -> gitlab_domain:string
  -> gitlab_repo_full_name:string
  -> context:string
  -> state:string
  -> external_id:string
  -> unit Lwt.t

val pipeline_action :
     bot_info:Bot_components.Bot_info.t
  -> Bot_components.GitLab_types.pipeline_info
  -> gitlab_mapping:(string, string) Base.Hashtbl.t
  -> ?full_ci_check_repo:(string * string) option
  -> ?auto_minimize_on_failure:(string * string) option
  -> unit
  -> unit Lwt.t
