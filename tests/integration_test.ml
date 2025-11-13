open Base
open Bot_components
open Config
open Config_resolver
open Repo_config
open Alcotest
open Test_helpers

(** Integration tests that verify end-to-end workflows and catch regressions.
    These tests verify that components work together correctly, not just in isolation.
    
    NOTE: These tests focus on UNIQUE integration scenarios not covered by unit tests.
    For config resolution, backport, multi-repo, cache, etc., see:
    - config_resolver_test.ml
    - refactored_code_backport_test.ml
    - repo_config_integration_test.ml
    - cache_test.ml
    - refactored_code_generic_test.ml
    *)

(** Test 1: Minimizer URL Configuration Integration
    Verifies that minimizer_url from TOML, env var, or None works correctly end-to-end.
    This is a regression test for making minimizer_url generic.
    
    Tests all configuration scenarios:
    1. TOML config only (explicit takes priority)
    2. Environment variable only (used when TOML is None)
    3. Both TOML and env var (TOML takes priority)
    4. Neither configured (returns None)
    *)
let test_minimizer_url_integration () =
  let bot_info = create_mock_bot_info () in
  (* Test case 1: TOML config only - explicit config takes priority *)
  let config_with_toml_minimizer =
    { github_owner= "test-org"
    ; github_repo= "test-repo"
    ; gitlab_domain= None
    ; gitlab_owner= None
    ; gitlab_repo= None
    ; github_installation_id= None
    ; github_project_number= None
    ; org_name= None
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
  (* Test case 2: Environment variable only - used when TOML is None *)
  (* Save original env var value if it exists *)
  (* Sys.getenv in Base returns string option directly, no exception *)
  let original_env_var = Sys.getenv "BOT_MINIMIZER_URL" in
  (* Set env var for this test *)
  Unix.putenv "BOT_MINIMIZER_URL" "https://env-minimizer.com" ;
  let config_without_minimizer =
    { github_owner= "test-org"
    ; github_repo= "test-repo"
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
    ; documentation= None }
  in
  let resolved_with_env =
    Lwt_main.run
      (resolve_repo_config ~bot_info ~explicit_config:config_without_minimizer)
  in
  (* Should use env var when TOML is None *)
  check (option string) "minimizer_url from env var when TOML is None"
    resolved_with_env.minimizer_url (Some "https://env-minimizer.com") ;
  (* Test case 2b: None when neither TOML nor env var is configured *)
  (* Clear env var by setting it to empty string (which gets treated as None) *)
  Unix.putenv "BOT_MINIMIZER_URL" "" ;
  let config_without_minimizer =
    { github_owner= "test-org"
    ; github_repo= "test-repo"
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
    ; documentation= None }
  in
  let resolved_no_minimizer =
    Lwt_main.run
      (resolve_repo_config ~bot_info ~explicit_config:config_without_minimizer)
  in
  (* Should be None when neither configured (empty string is treated as None) *)
  check (option string) "minimizer_url is None when not configured"
    resolved_no_minimizer.minimizer_url None ;
  (* Test case 3: Both TOML and env var - TOML takes priority *)
  (* Set env var to verify TOML takes priority *)
  Unix.putenv "BOT_MINIMIZER_URL" "https://env-should-be-ignored.com" ;
  (* This verifies the priority: Explicit > Auto-detected > Defaults *)
  (* Since TOML is explicit config, it should override env var (which is in defaults) *)
  let config_with_both =
    { github_owner= "test-org"
    ; github_repo= "test-repo"
    ; gitlab_domain= None
    ; gitlab_owner= None
    ; gitlab_repo= None
    ; github_installation_id= None
    ; github_project_number= None
    ; org_name= None
    ; team_name= None
    ; minimizer_url= Some "https://toml-priority.com"
    ; ci_config= None
    ; labels= None
    ; jobs= None
    ; documentation= None }
  in
  (* Even if env var was set, TOML should win *)
  let resolved_both =
    Lwt_main.run
      (resolve_repo_config ~bot_info ~explicit_config:config_with_both)
  in
  check (option string) "TOML minimizer_url takes priority over env var"
    resolved_both.minimizer_url (Some "https://toml-priority.com") ;
  (* Restore original env var at the end of all tests *)
  match original_env_var with
  | Some value ->
      Unix.putenv "BOT_MINIMIZER_URL" value
  | None ->
      (* Clear env var by setting to empty string *)
      Unix.putenv "BOT_MINIMIZER_URL" ""

(** Test 2: Feature Flag Integration
    Verifies that feature flags (backport, minimization, custom job status) work together *)
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
  (* Verify all feature flags are set *)
  check bool "backport enabled (project_number)"
    (Option.is_some config.github_project_number)
    true ;
  check bool "minimization enabled (minimizer_url)"
    (Option.is_some config.minimizer_url)
    true ;
  match config.jobs with
  | Some jobs ->
      (* Check that custom_job_status is explicitly enabled (Some true) *)
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
