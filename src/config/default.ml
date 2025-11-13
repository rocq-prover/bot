(** Generic defaults that work for any repository *)
let gitlab_domain = "gitlab.com"

let team_name = "maintainers"

let labels =
  { Repo_config.needs_rebase= Some "needs: rebase"
  ; stale= Some "stale"
  ; needs_full_ci= Some "needs: full CI"
  ; request_full_ci= Some "request: full CI"
  ; needs_independent_fix= Some "needs: independent fix" }

let ci_config =
  { Repo_config.full_ci_variable= Some "FULL_CI"
  ; skip_docker_variable= Some "SKIP_DOCKER"
  ; docker_path_pattern= Some ".*Dockerfile.*" }

(** Get minimizer URL from environment variable if set, otherwise None.
    This allows setting a global default via BOT_MINIMIZER_URL environment variable
    while keeping the code generic (no hardcoded repository-specific URLs). *)
let minimizer_url_from_env () =
  try match Sys.getenv "BOT_MINIMIZER_URL" with "" -> None | url -> Some url
  with Not_found -> None

let get_defaults ~owner ~repo =
  { Repo_config.github_owner= owner
  ; github_repo= repo
  ; gitlab_domain= Some gitlab_domain
  ; gitlab_owner= Some owner
  ; gitlab_repo= Some repo
  ; github_installation_id= None
  ; github_project_number= None
  ; org_name= Some owner
  ; team_name= Some team_name
  ; minimizer_url= minimizer_url_from_env ()
  ; ci_config= Some ci_config
  ; labels= Some labels
  ; jobs= None
  ; documentation= None }
