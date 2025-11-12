(** Repository-specific configuration types and parsing *)

type ci_config =
  { full_ci_variable: string option
  ; skip_docker_variable: string option
  ; docker_path_pattern: string option }

type label_config =
  { needs_rebase: string option
  ; stale: string option
  ; needs_full_ci: string option
  ; request_full_ci: string option
  ; needs_independent_fix: string option }

type job_config =
  { bench: string option
  ; doc_refman: string list option (* Pipe-separated string: "job1|job2" *)
  ; doc_init: string option
  ; doc_stdlib: string list option (* Pipe-separated string: "job1|job2" *)
  ; doc_ml_api: string option }

type doc_config =
  { refman_path: string option
  ; corelib_path: string option
  ; stdlib_path: string option
  ; ml_api_path: string option }

type t =
  { github_owner: string
  ; github_repo: string
  ; gitlab_domain: string option
  ; gitlab_owner: string option
  ; gitlab_repo: string option
  ; github_installation_id: int option
  ; github_project_number: int option
  ; org_name: string option
  ; team_name: string option
  ; minimizer_url: string option
  ; ci_config: ci_config option
  ; labels: label_config option
  ; jobs: job_config option
  ; documentation: doc_config option }

val parse_all_repo_configs : Toml.Types.table -> t list

val create_repo_config_table : Toml.Types.table -> (string, t) Base.Hashtbl.t

val get_repo_config_opt :
  owner:string -> repo:string -> (string, t) Base.Hashtbl.t -> t option

val has_repo_config :
  owner:string -> repo:string -> (string, t) Base.Hashtbl.t -> bool

val has_ci_config : t -> bool

val has_minimizer : t -> bool

val find_repo_with_ci_config :
  (string, t) Base.Hashtbl.t -> (string * string) option

val find_repo_with_minimizer :
  (string, t) Base.Hashtbl.t -> (string * string) option

val update_installation_id :
     owner:string
  -> repo:string
  -> install_id:int
  -> (string, t) Base.Hashtbl.t
  -> unit

val get_installation_id :
  owner:string -> repo:string -> (string, t) Base.Hashtbl.t -> int option
