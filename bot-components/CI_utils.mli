(******************************************************************************)
(* Types                                                                      *)
(******************************************************************************)

type artifact_info =
  | ArtifactInfo of
      {artifact_owner: string; artifact_repo: string; artifact_id: string}

type artifact_error =
  | ArtifactEmpty
  | ArtifactContainsMultipleFiles of string list
  | ArtifactDownloadError of string

type run_ci_minimization_error =
  | ArtifactError of
      {url: string; artifact: artifact_info; artifact_error: artifact_error}
  | DownloadError of {url: string; error: string}

type rocq_job_info =
  { docker_image: string
  ; dependencies: string list
  ; targets: string list
  ; compiler: string
  ; opam_variant: string }

type ci_minimization_info =
  { target: string
  ; full_target: string
  ; ci_targets: string list
  ; docker_image: string
  ; opam_switch: string
  ; failing_urls: string
  ; passing_urls: string }

type ci_minimization_job_suggestion_info =
  { base_job_failed: bool
  ; base_job_errored: string option
  ; head_job_succeeded: bool
  ; missing_error: bool
  ; non_v_file: string option
  ; job_kind: string
  ; job_target: string }

type ci_minimization_pr_info =
  { comment_thread_id: GitHub_ID.t
  ; base: string
  ; head: string
  ; pr_number: int
  ; draft: bool
  ; body: string
  ; labels: string list
  ; base_pipeline_finished: bool
  ; head_pipeline_finished: bool
  ; failed_test_suite_jobs: string list }

type ci_minimization_request =
  | Auto
  | RequestSuggested
  | RequestAll
  | RequestExplicit of string list

type ci_minimization_suggestion_kind =
  | Suggested
  | Possible of string
  | Bad of string

type ci_pr_minimization_suggestion =
  | Suggest
  | RunAutomatically
  | Silent of string

type build_failure = Warn of string | Retry of string | Ignore of string

(******************************************************************************)
(* GitLab Trace Processing Utilities                                         *)
(******************************************************************************)

val trace_action : repo_full_name:string -> string -> build_failure Lwt.t

(******************************************************************************)
(* Pipeline Summary and Error Formatting                                      *)
(******************************************************************************)

val create_pipeline_summary :
  ?summary_top:string -> GitLab_types.pipeline_info -> string -> string

val run_ci_minimization_error_to_string : run_ci_minimization_error -> string

(******************************************************************************)
(* CI Minimization Parsing Utilities                                         *)
(******************************************************************************)

val parse_quantity : string -> string -> (int, string) Result.t Lwt.t

val shorten_ci_check_name : string -> string

val format_options_for_getopts : string -> string

val getopts : string -> opt:string -> string list

val getopt : string -> opt:string -> string

val accumulate_extra_minimizer_arguments : string -> string list Lwt.t

(******************************************************************************)
(* GitHub Artifact Parsing                                                   *)
(******************************************************************************)

val parse_github_artifact_url : string -> artifact_info option

(******************************************************************************)
(* CI Status Check Functions                                                 *)
(******************************************************************************)

val send_status_check :
     bot_info:Bot_info.t
  -> GitLab_types.ci_common_info GitLab_types.job_info
  -> pr_num:int option
  -> string * string
  -> github_repo_full_name:string
  -> gitlab_domain:string
  -> gitlab_repo_full_name:string
  -> context:string
  -> failure_reason:string
  -> external_id:string
  -> trace:string
  -> unit Lwt.t

(******************************************************************************)
(* CI Minimization Core Functions                                            *)
(******************************************************************************)

val ci_minimization_extract_job_specific_info :
     head_pipeline_summary:string
  -> base_pipeline_summary:string
  -> base_checks_errors:(string * string) list
  -> base_checks:(GitHub_types.check_tab_info * bool) list
  -> GitHub_types.check_tab_info * bool
  -> ( ci_minimization_job_suggestion_info * ci_minimization_info
     , string )
     Result.t

val fetch_ci_minimization_info :
     bot_info:Bot_info.t
  -> owner:string
  -> repo:string
  -> pr_number:int
  -> head_pipeline_summary:string option
  -> ?base_sha:string
  -> ?head_sha:string
  -> unit
  -> ( ci_minimization_pr_info
       * (ci_minimization_job_suggestion_info * ci_minimization_info) list
       * (string * string) list
     , GitHub_ID.t option * string )
     Result.t
     Lwt.t

val ci_minimization_suggest :
     base:string
  -> ci_minimization_job_suggestion_info
  -> ci_minimization_suggestion_kind

val suggest_ci_minimization_for_pr :
  ci_minimization_pr_info -> ci_pr_minimization_suggestion
