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

let minimizer_url =
  "https://github.com/rocq-community/run-coq-bug-minimizer/actions"

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
  ; minimizer_url= Some minimizer_url
  ; ci_config= Some ci_config
  ; labels= Some labels
  ; jobs= None
  ; documentation= None }
