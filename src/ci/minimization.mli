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
  { comment_thread_id: Bot_components.GitHub_ID.t
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

(******************************************************************************)
(* CI Minimization Parsing Utilities                                          *)
(******************************************************************************)

val accumulate_extra_minimizer_arguments : string -> string list Lwt.t

val run_ci_minimization_error_to_string : run_ci_minimization_error -> string

(******************************************************************************)
(* GitHub Artifact Parsing                                                    *)
(******************************************************************************)

val parse_github_artifact_url : string -> artifact_info option
(******************************************************************************)
(* CI Minimization Core Functions                                             *)
(******************************************************************************)

val run_ci_minimization :
     bot_info:Bot_components.Bot_info.t
  -> comment_thread_id:Bot_components.GitHub_ID.t
  -> owner:string
  -> repo:string
  -> pr_number:string
  -> base:string
  -> head:string
  -> ci_minimization_infos:ci_minimization_info list
  -> bug_file:Bot_components.Minimize_parser.minimize_parsed option
  -> minimizer_extra_arguments:string list
  -> (string list * (string * string) list, run_ci_minimization_error) Result.t
     Lwt.t

val ci_minimization_extract_job_specific_info :
     head_pipeline_summary:string
  -> base_pipeline_summary:string
  -> base_checks_errors:(string * string) list
  -> base_checks:(Bot_components.GitHub_types.check_tab_info * bool) list
  -> Bot_components.GitHub_types.check_tab_info * bool
  -> ( ci_minimization_job_suggestion_info * ci_minimization_info
     , string )
     Result.t

val fetch_ci_minimization_info :
     bot_info:Bot_components.Bot_info.t
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
     , Bot_components.GitHub_ID.t option * string )
     Result.t
     Lwt.t

val ci_minimization_suggest :
     base:string
  -> ci_minimization_job_suggestion_info
  -> ci_minimization_suggestion_kind

val suggest_ci_minimization_for_pr :
  ci_minimization_pr_info -> ci_pr_minimization_suggestion

val minimize_failed_tests :
     bot_info:Bot_components.Bot_info.t
  -> owner:string
  -> repo:string
  -> pr_number:int
  -> head_pipeline_summary:string option
  -> request:ci_minimization_request
  -> comment_on_error:bool
  -> bug_file:Bot_components.Minimize_parser.minimize_parsed option
  -> options:string
  -> ?base_sha:string
  -> ?head_sha:string
  -> unit
  -> unit Lwt.t

val ci_minimize :
     bot_info:Bot_components.Bot_info.t
  -> comment_info:Bot_components.GitHub_types.comment_info
  -> requests:string list
  -> comment_on_error:bool
  -> options:string
  -> bug_file:Bot_components.Minimize_parser.minimize_parsed option
  -> unit Lwt.t

val run_coq_minimizer :
     bot_info:Bot_components.Bot_info.t
  -> script:Bot_components.Minimize_parser.minimize_parsed
  -> comment_thread_id:Bot_components.GitHub_ID.t
  -> comment_author:string
  -> owner:string
  -> repo:string
  -> options:string
  -> minimizer_url:string
  -> unit Lwt.t

val coq_bug_minimizer_results_action :
     bot_info:Bot_components.Bot_info.t
  -> ci:bool
  -> key:Mirage_crypto_pk.Rsa.priv
  -> app_id:int
  -> string
  -> (Cohttp.Response.t * Cohttp_lwt__Body.t) Lwt.t

val coq_bug_minimizer_resume_ci_minimization_action :
     bot_info:Bot_components.Bot_info.t
  -> key:Mirage_crypto_pk.Rsa.priv
  -> app_id:int
  -> string
  -> (Cohttp.Response.t * Cohttp_lwt__Body.t) Lwt.t
