open Base

module BenchResults : sig
  type t =
    { summary_table: string
    ; failures: string
    ; slow_table: string
    ; slow_number: int
    ; fast_table: string
    ; fast_number: int }
end

val fetch_bench_results :
     job_info:
       Bot_components.GitLab_types.ci_common_info
       Bot_components.GitLab_types.job_info
  -> unit
  -> (BenchResults.t, string) Result.t Lwt.t

val bench_text : (BenchResults.t, string) Result.t -> string Lwt.t

val bench_comment :
     bot_info:Bot_components.Bot_info.t
  -> owner:string
  -> repo:string
  -> number:int
  -> gitlab_url:string
  -> ?check_url:string
  -> (BenchResults.t, string) Result.t
  -> unit Lwt.t

val update_bench_status :
     bot_info:Bot_components.Bot_info.t
  -> repo_config_table:(string, Repo_config.t) Base.Hashtbl.t
  -> job_info:
       Bot_components.GitLab_types.ci_common_info
       Bot_components.GitLab_types.job_info
  -> string * string
  -> external_id:string
  -> number:int option
  -> unit Lwt.t

val run_bench :
     bot_info:Bot_components.Bot_info.t
  -> repo_config_table:(string, Repo_config.t) Base.Hashtbl.t
  -> ?key_value_pairs:(string * string) list
  -> Bot_components.GitHub_types.comment_info
  -> unit Lwt.t
