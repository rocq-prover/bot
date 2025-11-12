open Base
open Repo_config
open Alcotest
open Refactored_code_test_helpers

(** Tests for backport feature (actions/backport.ml) *)

let test_backport_feature_enabled () =
  (* Test that backport feature works when project_number is configured *)
  let table =
    create_generic_config ~owner:"test-org" ~repo:"test-repo" ~project_number:11
      ()
  in
  match get_repo_config_opt ~owner:"test-org" ~repo:"test-repo" table with
  | Some config ->
      (* Backport should be enabled (project_number is set) *)
      check (option int) "backport enabled" config.github_project_number
        (Some 11) ;
      check bool "backport feature enabled"
        (Option.is_some config.github_project_number)
        true
  | None ->
      fail "Expected config for backport test"

let test_backport_feature_disabled () =
  (* Test that backport feature is disabled when project_number is not set *)
  let table = create_generic_config ~owner:"test-org" ~repo:"test-repo" () in
  match get_repo_config_opt ~owner:"test-org" ~repo:"test-repo" table with
  | Some config ->
      (* Backport should be disabled (no project_number) *)
      check (option int) "backport disabled" config.github_project_number None ;
      check bool "backport feature disabled"
        (Option.is_none config.github_project_number)
        true
  | None ->
      fail "Expected config for backport test"

let test_rocq_backport_still_works () =
  (* Test that rocq backport still works *)
  let table = create_rocq_config () in
  match get_repo_config_opt ~owner:"rocq-prover" ~repo:"rocq" table with
  | Some config ->
      (* Rocq should have project_number configured *)
      check (option int) "rocq backport enabled" config.github_project_number
        (Some 11) ;
      check bool "rocq backport feature enabled"
        (Option.is_some config.github_project_number)
        true
  | None ->
      fail "Expected rocq config for backport test"

let () =
  run "Refactored Code - Backport"
    [ ( "backport"
      , [ test_case "backport feature enabled" `Quick
            test_backport_feature_enabled
        ; test_case "backport feature disabled" `Quick
            test_backport_feature_disabled
        ; test_case "rocq backport still works" `Quick
            test_rocq_backport_still_works ] ) ]
