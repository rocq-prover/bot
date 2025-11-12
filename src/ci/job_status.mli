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
  -> repo_config_table:(string, Repo_config.t) Base.Hashtbl.t
  -> Bot_components.GitLab_types.pipeline_info
  -> gitlab_mapping:(string, string) Base.Hashtbl.t
  -> ?full_ci_check_repo:(string * string) option
  -> ?auto_minimize_on_failure:(string * string) option
  -> unit
  -> unit Lwt.t

(** Custom job info extracted from CI trace *)
type custom_job_info =
  { docker_image: string
  ; dependencies: string list
  ; targets: string list
  ; compiler: string
  ; opam_variant: string }

val extract_custom_job_info : string list -> custom_job_info option
(** Extract job information from trace lines (Docker image, dependencies, targets, compiler, opam variant) *)

val build_custom_summary_tail :
  custom_job_info option -> trace_description:string -> string
(** Build summary tail from custom job info and trace description *)

val handle_custom_allow_failure :
     bot_info:Bot_components.Bot_info.t
  -> job_name:string
  -> job_url:string
  -> pr_num:int option
  -> head_commit:string
  -> string * string
  -> gitlab_repo_full_name:string
  -> unit Lwt.t
(** Handle allow-failure cases (currently has specific handler for library:ci-fiat_crypto_legacy) *)

val custom_summary_builder : string list -> string -> string Lwt.t
(** Create a summary builder function for repositories with custom job status handling.
    Returns a function that takes trace_description and returns the summary tail. *)
