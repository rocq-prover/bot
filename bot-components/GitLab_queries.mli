val get_build_trace :
     bot_info:Bot_info.t
  -> gitlab_domain:string
  -> project_id:int
  -> build_id:int
  -> (string, string) Lwt_result.t

val get_retry_nb :
     bot_info:Bot_info.t
  -> gitlab_domain:string
  -> full_name:string
  -> build_id:int
  -> build_name:string
  -> (int, string) Lwt_result.t

val search_projects :
     bot_info:Bot_info.t
  -> gitlab_domain:string
  -> search_term:string
  -> ?timeout:float
  -> unit
  -> (GitLab_types.project_info list, string) result Lwt.t
(** Search projects with timeout (default 5 seconds) *)

val get_ci_config_file :
     bot_info:Bot_info.t
  -> gitlab_domain:string
  -> full_path:string
  -> ?timeout:float
  -> unit
  -> (string option, string) result Lwt.t
(** Get CI config file with timeout (default 5 seconds) *)
