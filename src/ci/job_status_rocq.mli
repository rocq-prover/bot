(** Rocq-specific CI job status handling *)

type rocq_job_info =
  { docker_image: string
  ; dependencies: string list
  ; targets: string list
  ; compiler: string
  ; opam_variant: string }

val extract_rocq_job_info : string list -> rocq_job_info option
(** Extract Rocq-specific job information from trace lines *)

val build_rocq_summary_tail :
  rocq_job_info option -> trace_description:string -> string
(** Build summary tail from Rocq job info and trace description *)

val handle_rocq_allow_failure :
     bot_info:Bot_components.Bot_info.t
  -> job_name:string
  -> job_url:string
  -> pr_num:int option
  -> head_commit:string
  -> string * string
  -> gitlab_repo_full_name:string
  -> unit Lwt.t
(** Handle Rocq-specific allow-failure cases (e.g., library:ci-fiat_crypto_legacy) *)

val rocq_summary_builder : string list -> string -> string Lwt.t
(** Create a summary builder function for Rocq repositories.
    Returns a function that takes trace_description and returns the summary tail. *)
