open Base
open Repo_config
open Alcotest
open Refactored_code_test_helpers

(** Tests for documentation URLs (ci/documentation.ml) *)

let test_documentation_configuration () =
  (* Test that documentation paths are configurable *)
  let table = create_rocq_config () in
  match get_repo_config_opt ~owner:"rocq-prover" ~repo:"rocq" table with
  | Some config -> (
    match config.documentation with
    | Some doc ->
        (* Verify all documentation paths are configurable *)
        check (option string) "refman_path" doc.refman_path
          (Some "_build/default/doc/refman-html/index.html") ;
        check (option string) "corelib_path" doc.corelib_path
          (Some "_build/default/doc/corelib/html/index.html") ;
        check (option string) "stdlib_path" doc.stdlib_path
          (Some "_build/default/doc/stdlib/html/index.html") ;
        check (option string) "ml_api_path" doc.ml_api_path
          (Some "_build/default/_doc/_html/index.html")
    | None ->
        fail "Expected documentation config" )
  | None ->
      fail "Expected rocq config for documentation test"

let test_documentation_requires_config () =
  (* Test that documentation feature requires config (no fallback) *)
  let table = create_generic_config ~owner:"test-org" ~repo:"test-repo" () in
  match get_repo_config_opt ~owner:"test-org" ~repo:"test-repo" table with
  | Some config ->
      (* Documentation should be None (feature requires explicit config) *)
      check bool "documentation requires config"
        (Option.is_none config.documentation)
        true
  | None ->
      fail "Expected config for documentation test"

let () =
  run "Refactored Code - Documentation"
    [ ( "documentation"
      , [ test_case "documentation configuration" `Quick
            test_documentation_configuration
        ; test_case "documentation requires config" `Quick
            test_documentation_requires_config ] ) ]
