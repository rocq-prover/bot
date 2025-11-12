open Base
open Repo_config
open Alcotest
open Refactored_code_test_helpers

(** Tests for CI protection, labels, and CI config (actions/pr_sync.ml) *)

let test_ci_protection_enabled () =
  (* Test that CI protection works when org_name and team_name are configured *)
  let table =
    create_generic_config ~owner:"test-org" ~repo:"test-repo"
      ~org_name:"test-org" ~team_name:"maintainers" ~gitlab_domain:"gitlab.com"
      ()
  in
  match get_repo_config_opt ~owner:"test-org" ~repo:"test-repo" table with
  | Some config ->
      (* CI protection should be enabled (org_name and team_name are set) *)
      check (option string) "org_name configured" config.org_name
        (Some "test-org") ;
      check (option string) "team_name configured" config.team_name
        (Some "maintainers") ;
      check bool "CI protection enabled"
        (Option.is_some config.org_name && Option.is_some config.team_name)
        true
  | None ->
      fail "Expected config for CI protection test"

let test_ci_protection_disabled () =
  (* Test that CI protection is disabled when org_name or team_name is missing *)
  let table = create_generic_config ~owner:"test-org" ~repo:"test-repo" () in
  match get_repo_config_opt ~owner:"test-org" ~repo:"test-repo" table with
  | Some config ->
      (* CI protection should be disabled (missing org_name or team_name) *)
      let protection_enabled =
        Option.is_some config.org_name && Option.is_some config.team_name
      in
      check bool "CI protection disabled" protection_enabled false
  | None ->
      fail "Expected config for CI protection test"

let test_rocq_ci_protection_still_works () =
  (* Test that rocq CI protection still works *)
  let table = create_rocq_config () in
  match get_repo_config_opt ~owner:"rocq-prover" ~repo:"rocq" table with
  | Some config ->
      (* Rocq should have org_name and team_name configured *)
      check (option string) "rocq org_name" config.org_name (Some "rocq-prover") ;
      check (option string) "rocq team_name" config.team_name
        (Some "contributors") ;
      check bool "rocq CI protection enabled"
        (Option.is_some config.org_name && Option.is_some config.team_name)
        true
  | None ->
      fail "Expected rocq config for CI protection test"

let test_labels_configuration () =
  (* Test that labels are configurable (not hardcoded) *)
  let table = create_rocq_config () in
  match get_repo_config_opt ~owner:"rocq-prover" ~repo:"rocq" table with
  | Some config -> (
    match config.labels with
    | Some labels ->
        (* Verify all labels are configurable *)
        check (option string) "needs_rebase label" labels.needs_rebase
          (Some "needs: rebase") ;
        check (option string) "stale label" labels.stale (Some "stale") ;
        check (option string) "needs_full_ci label" labels.needs_full_ci
          (Some "needs: full CI") ;
        check (option string) "request_full_ci label" labels.request_full_ci
          (Some "request: full CI") ;
        check (option string) "needs_independent_fix label"
          labels.needs_independent_fix (Some "needs: independent fix")
    | None ->
        fail "Expected labels config" )
  | None ->
      fail "Expected rocq config for labels test"

let test_labels_fallback_to_defaults () =
  (* Test that labels fall back to defaults when not configured *)
  let table = create_generic_config ~owner:"test-org" ~repo:"test-repo" () in
  match get_repo_config_opt ~owner:"test-org" ~repo:"test-repo" table with
  | Some config ->
      (* Labels should be None (will use defaults in code) *)
      check bool "labels fallback" (Option.is_none config.labels) true
  | None ->
      fail "Expected config for labels test"

let test_ci_config_configuration () =
  (* Test that CI config is configurable (not hardcoded) *)
  let table = create_rocq_config () in
  match get_repo_config_opt ~owner:"rocq-prover" ~repo:"rocq" table with
  | Some config -> (
    match config.ci_config with
    | Some ci ->
        (* Verify all CI config values are configurable *)
        check (option string) "full_ci_variable" ci.full_ci_variable
          (Some "FULL_CI") ;
        check (option string) "skip_docker_variable" ci.skip_docker_variable
          (Some "SKIP_DOCKER") ;
        check (option string) "docker_path_pattern" ci.docker_path_pattern
          (Some "dev/ci/docker/.*Dockerfile.*")
    | None ->
        fail "Expected CI config" )
  | None ->
      fail "Expected rocq config for CI config test"

let test_ci_config_fallback_to_defaults () =
  (* Test that CI config falls back to defaults when not configured *)
  let table = create_generic_config ~owner:"test-org" ~repo:"test-repo" () in
  match get_repo_config_opt ~owner:"test-org" ~repo:"test-repo" table with
  | Some config ->
      (* CI config should be None (will use defaults in code) *)
      check bool "CI config fallback" (Option.is_none config.ci_config) true
  | None ->
      fail "Expected config for CI config test"

let () =
  run "Refactored Code - CI"
    [ ( "ci_protection"
      , [ test_case "CI protection enabled" `Quick test_ci_protection_enabled
        ; test_case "CI protection disabled" `Quick test_ci_protection_disabled
        ; test_case "rocq CI protection still works" `Quick
            test_rocq_ci_protection_still_works ] )
    ; ( "labels"
      , [ test_case "labels configuration" `Quick test_labels_configuration
        ; test_case "labels fallback to defaults" `Quick
            test_labels_fallback_to_defaults ] )
    ; ( "ci_config"
      , [ test_case "CI config configuration" `Quick test_ci_config_configuration
        ; test_case "CI config fallback to defaults" `Quick
            test_ci_config_fallback_to_defaults ] ) ]
