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

val gitlab_job_url :
     gitlab_domain:string option
  -> gitlab_owner:string option
  -> gitlab_repo:string option
  -> job_id:int
  -> string option

val bench_summary_job_link_prefix :
     gitlab_domain:string option
  -> gitlab_owner:string option
  -> gitlab_repo:string option
  -> job_name:string
  -> string option

val bench_summary_build_id_regex :
     gitlab_domain:string option
  -> gitlab_owner:string option
  -> gitlab_repo:string option
  -> job_name:string
  -> string option

val fetch_bench_results :
     job_info:GitLab_types.ci_common_info GitLab_types.job_info
  -> unit
  -> (BenchResults.t, string) Result.t Lwt.t

val bench_text : (BenchResults.t, string) Result.t -> string Lwt.t

val bench_comment :
     bot_info:Bot_info.t
  -> owner:string
  -> repo:string
  -> number:int
  -> gitlab_url:string
  -> ?check_url:string
  -> (BenchResults.t, string) Result.t
  -> unit Lwt.t

val update_bench_status :
     bot_info:Bot_info.t
  -> job_info:GitLab_types.ci_common_info GitLab_types.job_info
  -> string * string
  -> external_id:string
  -> number:int option
  -> gitlab_domain:string option
  -> gitlab_owner:string option
  -> gitlab_repo:string option
  -> unit Lwt.t

val run_bench :
     bot_info:Bot_info.t
  -> ?org:string
  -> ?team:string
  -> gitlab_domain:string option
  -> gitlab_owner:string option
  -> gitlab_repo:string option
  -> bench_job:string
  -> ?key_value_pairs:(string * string) list
  -> GitHub_types.comment_info
  -> unit Lwt.t
