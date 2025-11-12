open Base
open Repo_config
open Alcotest
open Refactored_code_test_helpers

(** Tests for bench commands (utils/bench.ml) *)

let test_bench_requires_config () =
  (* Test that bench commands require org_name, team_name, and gitlab_domain *)
  let table =
    create_generic_config ~owner:"test-org" ~repo:"test-repo"
      ~org_name:"test-org" ~team_name:"maintainers" ~gitlab_domain:"gitlab.com"
      ()
  in
  match get_repo_config_opt ~owner:"test-org" ~repo:"test-repo" table with
  | Some config ->
      (* All required fields should be present *)
      check (option string) "bench org_name" config.org_name (Some "test-org") ;
      check (option string) "bench team_name" config.team_name
        (Some "maintainers") ;
      check (option string) "bench gitlab_domain" config.gitlab_domain
        (Some "gitlab.com") ;
      check bool "bench config complete"
        ( Option.is_some config.org_name
        && Option.is_some config.team_name
        && Option.is_some config.gitlab_domain )
        true
  | None ->
      fail "Expected config for bench test"

let test_rocq_bench_still_works () =
  (* Test that rocq bench commands still work *)
  let table = create_rocq_config () in
  match get_repo_config_opt ~owner:"rocq-prover" ~repo:"rocq" table with
  | Some config ->
      (* Rocq should have all required fields *)
      check (option string) "rocq bench org_name" config.org_name
        (Some "rocq-prover") ;
      check (option string) "rocq bench team_name" config.team_name
        (Some "contributors") ;
      check (option string) "rocq bench gitlab_domain" config.gitlab_domain
        (Some "gitlab.inria.fr") ;
      check bool "rocq bench config complete"
        ( Option.is_some config.org_name
        && Option.is_some config.team_name
        && Option.is_some config.gitlab_domain )
        true
  | None ->
      fail "Expected rocq config for bench test"

let () =
  run "Refactored Code - Bench"
    [ ( "bench_commands"
      , [ test_case "bench requires config" `Quick test_bench_requires_config
        ; test_case "rocq bench still works" `Quick test_rocq_bench_still_works
        ] ) ]
