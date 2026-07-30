type repo_jobs_config =
  { bench_job: string option
  ; use_rocq_job_status: bool
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
  ; jobs: repo_jobs_config }

val make_repo_config_table : Toml.Types.table -> (string, t) Base.Hashtbl.t

val find_by_github :
  owner:string -> repo:string -> (string, t) Base.Hashtbl.t -> t option
