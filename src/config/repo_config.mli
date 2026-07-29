type repo_jobs_config =
  {bench: string option; custom_job_status: bool; doc_jobs: string list}

type t =
  { github_owner: string
  ; github_repo: string
  ; gitlab_domain: string option
  ; gitlab_owner: string option
  ; gitlab_repo: string option
  ; github_project_number: int option
  ; github_installation_id: int option
  ; org_name: string option
  ; team_name: string option
  ; pushers_team: string option
  ; maintainers_team: string option
  ; minimizer_url: string option
  ; jobs: repo_jobs_config }

val make_repo_config_table : Toml.Types.table -> (string, t) Base.Hashtbl.t

val find_by_github :
  owner:string -> repo:string -> (string, t) Base.Hashtbl.t -> t option
