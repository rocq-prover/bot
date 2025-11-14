open Base
open Bot_components
open Config
open Config_resolver
open Repo_config
open Alcotest
open Test_helpers

(** Integration tests for end-to-end workflows. *)

(** Tests minimizer_url configuration: TOML, env var, or None *)
let test_minimizer_url_integration () =
  let bot_info = create_mock_bot_info () in
  (* Case 1: TOML config only *)
  let config_with_toml_minimizer =
    { github_owner= "test-org"
    ; github_repo= "test-repo"
    ; gitlab_domain= Some "gitlab.com"
    ; gitlab_owner= None
    ; gitlab_repo= None
    ; github_installation_id= None
    ; github_project_number= None
    ; org_name= Some "test-org"
    ; team_name= None
    ; minimizer_url= Some "https://toml-minimizer.com"
    ; ci_config= None
    ; labels= None
    ; jobs= None
    ; documentation= None }
  in
  let resolved_toml =
    Lwt_main.run
      (resolve_repo_config ~bot_info ~explicit_config:config_with_toml_minimizer)
  in
  check (option string) "TOML minimizer_url preserved"
    resolved_toml.minimizer_url (Some "https://toml-minimizer.com") ;
  (* Case 2: Environment variable only *)
  let original_env_var = Sys.getenv "BOT_MINIMIZER_URL" in
  Unix.putenv "BOT_MINIMIZER_URL" "https://env-minimizer.com" ;
  let config_without_minimizer =
    { github_owner= "test-org"
    ; github_repo= "test-repo"
    ; gitlab_domain= Some "gitlab.com"
    ; gitlab_owner= None
    ; gitlab_repo= None
    ; github_installation_id= None
    ; github_project_number= None
    ; org_name= Some "test-org"
    ; team_name= None
    ; minimizer_url= None
    ; ci_config= None
    ; labels= None
    ; jobs= None
    ; documentation= None }
  in
  let resolved_with_env =
    Lwt_main.run
      (resolve_repo_config ~bot_info ~explicit_config:config_without_minimizer)
  in
  check (option string) "minimizer_url from env var when TOML is None"
    resolved_with_env.minimizer_url (Some "https://env-minimizer.com") ;
  (* Case 3: Neither configured (returns None) *)
  Unix.putenv "BOT_MINIMIZER_URL" "" ;
  let config_without_minimizer =
    { github_owner= "test-org"
    ; github_repo= "test-repo"
    ; gitlab_domain= Some "gitlab.com"
    ; gitlab_owner= None
    ; gitlab_repo= None
    ; github_installation_id= None
    ; github_project_number= None
    ; org_name= Some "test-org"
    ; team_name= None
    ; minimizer_url= None
    ; ci_config= None
    ; labels= None
    ; jobs= None
    ; documentation= None }
  in
  let resolved_no_minimizer =
    Lwt_main.run
      (resolve_repo_config ~bot_info ~explicit_config:config_without_minimizer)
  in
  check (option string) "minimizer_url is None when not configured"
    resolved_no_minimizer.minimizer_url None ;
  (* Case 4: Both TOML and env var (TOML takes priority) *)
  Unix.putenv "BOT_MINIMIZER_URL" "https://env-should-be-ignored.com" ;
  let config_with_both =
    { github_owner= "test-org"
    ; github_repo= "test-repo"
    ; gitlab_domain= Some "gitlab.com"
    ; gitlab_owner= None
    ; gitlab_repo= None
    ; github_installation_id= None
    ; github_project_number= None
    ; org_name= Some "test-org"
    ; team_name= None
    ; minimizer_url= Some "https://toml-priority.com"
    ; ci_config= None
    ; labels= None
    ; jobs= None
    ; documentation= None }
  in
  let resolved_both =
    Lwt_main.run
      (resolve_repo_config ~bot_info ~explicit_config:config_with_both)
  in
  check (option string) "TOML minimizer_url takes priority over env var"
    resolved_both.minimizer_url (Some "https://toml-priority.com") ;
  (* Restore original env var *)
  match original_env_var with
  | Some value ->
      Unix.putenv "BOT_MINIMIZER_URL" value
  | None ->
      Unix.putenv "BOT_MINIMIZER_URL" ""

(** Tests that feature flags work together *)
let test_feature_flags_integration () =
  let toml_str =
    {|
[repositories.full-featured]
github = "org/repo"
github_project_number = "10"
minimizer_url = "https://minimizer.com"

[repositories.full-featured.jobs]
custom_job_status = true
bench = "bench"
|}
  in
  let toml_data = Utils.toml_of_string toml_str in
  let table = repo_config_table toml_data in
  let config =
    Option.value_exn (get_repo_config_opt ~owner:"org" ~repo:"repo" table)
  in
  check bool "backport enabled (project_number)"
    (Option.is_some config.github_project_number)
    true ;
  check bool "minimization enabled (minimizer_url)"
    (Option.is_some config.minimizer_url)
    true ;
  match config.jobs with
  | Some jobs ->
      check (option bool) "custom job status enabled" jobs.custom_job_status
        (Some true) ;
      check (option string) "bench job configured" jobs.bench (Some "bench")
  | None ->
      Alcotest.fail "Expected jobs config"

let () =
  run "Integration"
    [ ( "minimizer_url"
      , [ test_case "minimizer_url configuration integration" `Quick
            test_minimizer_url_integration ] )
    ; ( "feature_flags"
      , [ test_case "feature flags integration" `Quick
            test_feature_flags_integration ] ) ]
