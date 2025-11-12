open Repo_config
open Lwt.Syntax

(* Merge two optional values with priority to the first *)
let merge_option opt1 opt2 = match opt1 with Some _ -> opt1 | None -> opt2

(* Merge nested config structures *)
let merge_ci_config opt1 opt2 =
  match (opt1, opt2) with
  | Some c1, Some c2 ->
      Some
        { full_ci_variable= merge_option c1.full_ci_variable c2.full_ci_variable
        ; skip_docker_variable=
            merge_option c1.skip_docker_variable c2.skip_docker_variable
        ; docker_path_pattern=
            merge_option c1.docker_path_pattern c2.docker_path_pattern }
  | Some c, None | None, Some c ->
      Some c
  | None, None ->
      None

let merge_label_config opt1 opt2 =
  match (opt1, opt2) with
  | Some l1, Some l2 ->
      Some
        { needs_rebase= merge_option l1.needs_rebase l2.needs_rebase
        ; stale= merge_option l1.stale l2.stale
        ; needs_full_ci= merge_option l1.needs_full_ci l2.needs_full_ci
        ; request_full_ci= merge_option l1.request_full_ci l2.request_full_ci
        ; needs_independent_fix=
            merge_option l1.needs_independent_fix l2.needs_independent_fix }
  | Some l, None | None, Some l ->
      Some l
  | None, None ->
      None

(* Merge two configurations with priority: Explicit > API > Defaults *)
let merge_configs explicit auto_detected defaults =
  { github_owner= explicit.github_owner
  ; github_repo= explicit.github_repo
  ; gitlab_domain=
      merge_option explicit.gitlab_domain
        (merge_option auto_detected.gitlab_domain defaults.gitlab_domain)
  ; gitlab_owner=
      merge_option explicit.gitlab_owner
        (merge_option auto_detected.gitlab_owner defaults.gitlab_owner)
  ; gitlab_repo=
      merge_option explicit.gitlab_repo
        (merge_option auto_detected.gitlab_repo defaults.gitlab_repo)
  ; github_installation_id=
      merge_option explicit.github_installation_id
        auto_detected.github_installation_id
  ; github_project_number=
      merge_option explicit.github_project_number
        auto_detected.github_project_number
  ; org_name=
      merge_option explicit.org_name
        (merge_option auto_detected.org_name defaults.org_name)
  ; team_name=
      merge_option explicit.team_name
        (merge_option auto_detected.team_name defaults.team_name)
  ; minimizer_url=
      merge_option explicit.minimizer_url
        (merge_option auto_detected.minimizer_url defaults.minimizer_url)
  ; ci_config=
      merge_ci_config explicit.ci_config
        (merge_option auto_detected.ci_config defaults.ci_config)
  ; labels=
      merge_label_config explicit.labels
        (merge_option auto_detected.labels defaults.labels)
  ; jobs=
      merge_option explicit.jobs (merge_option auto_detected.jobs defaults.jobs)
  ; documentation=
      merge_option explicit.documentation auto_detected.documentation }

(* Resolve final configuration with priority: Explicit > API > Defaults.
   Only runs auto-detection if explicit config is missing fields. *)
let resolve_repo_config ~bot_info ~explicit_config =
  let github_owner = explicit_config.github_owner in
  let github_repo = explicit_config.github_repo in
  (* Step 1: Get defaults *)
  let defaults = Default.get_defaults ~owner:github_owner ~repo:github_repo in
  (* Step 2: Check if we need auto-detection (only if key fields are missing) *)
  let needs_auto_detection =
    Option.is_none explicit_config.gitlab_domain
    || Option.is_none explicit_config.org_name
  in
  let* auto_detected =
    if needs_auto_detection then (
      Printf.printf "Running auto-detection for %s/%s\n%!" github_owner
        github_repo ;
      Auto_detection.auto_detect_from_apis ~bot_info ~github_owner ~github_repo
      )
    else (
      Printf.printf
        "Skipping auto-detection for %s/%s (explicit config present)\n%!"
        github_owner github_repo ;
      Lwt.return
        { Repo_config.github_owner
        ; github_repo
        ; gitlab_domain= None
        ; gitlab_owner= None
        ; gitlab_repo= None
        ; github_installation_id= None
        ; github_project_number= None
        ; org_name= None
        ; team_name= None
        ; minimizer_url= None
        ; ci_config= None
        ; labels= None
        ; jobs= None
        ; documentation= None } )
  in
  (* Step 3: Merge with priority: Explicit > API > Defaults *)
  Lwt.return (merge_configs explicit_config auto_detected defaults)
