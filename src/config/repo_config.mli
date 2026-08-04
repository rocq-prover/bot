type repo_jobs_config =
  { bench_job: string option
  ; use_rocq_job_status: bool
  ; silence_docker_manifest_errors: bool
  ; doc_artifact_jobs: string list }

type backport_config = {github_project_number: int option}

type team_permission = {team_name: string; permission: string}

type t =
  { github_owner: string
  ; github_repo: string
  ; gitlab_domain: string option
  ; gitlab_owner: string option
  ; gitlab_repo: string option
  ; backporting: backport_config
  ; github_installation_id: int option
  ; org_name: string option
  ; alert_mention: string option
  ; teams: team_permission list
  ; minimizer_url: string option
  ; contributing_url: string option
  ; jobs: repo_jobs_config }

val make_repo_config_table : Toml.Types.table -> (string, t) Base.Hashtbl.t

val find_by_github :
  owner:string -> repo:string -> (string, t) Base.Hashtbl.t -> t option

val project_organization : t -> string

val backport_enabled : t -> bool

val find_by_backport_project :
  install_id:int -> project_number:int -> (string, t) Base.Hashtbl.t -> t option

val is_bench_job : t -> string -> bool

val is_doc_artifact_job : t -> string -> bool

val github_full_name : t -> string

val gitlab_job_url : t -> job_id:int -> string option

val gitlab_pages_artifact_url :
  t -> job_id:int -> artifact:string -> string option

val team_for_permission : t -> string -> string option

val team_mention : t -> permission:string -> string option

val should_send_welcome_message :
  t -> same_branch_name:bool -> opened:bool -> bool
