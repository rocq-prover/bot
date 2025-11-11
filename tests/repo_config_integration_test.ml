open Base
open Bot_components
open Config
open Repo_config
open Alcotest
open Repo_config_test_helpers

(* Integration tests for repo_config loading from TOML files *)

let test_load_from_toml_file () =
  (* Test loading configuration from an actual TOML file *)
  let config_file = "test-config.toml" in
  let toml_data = Utils.toml_of_file config_file in
  let table = repo_config_table toml_data in
  (* Verify the table was created *)
  (* test-config.toml contains 3 repositories: rocq, coq, and opam *)
  check int "table should have 3 repositories" 3 (Hashtbl.length table) ;
  (* Verify rocq-prover/rocq config *)
  check bool "should have rocq config"
    (has_repo_config ~owner:"rocq-prover" ~repo:"rocq" table)
    true ;
  let rocq_config =
    Option.value_exn
      (get_repo_config_opt ~owner:"rocq-prover" ~repo:"rocq" table)
  in
  check string "rocq github_owner" rocq_config.github_owner "rocq-prover" ;
  check string "rocq github_repo" rocq_config.github_repo "rocq" ;
  check (option int) "rocq installation_id" rocq_config.github_installation_id
    (Some 1062161) ;
  check (option int) "rocq project_number" rocq_config.github_project_number
    (Some 11) ;
  check (option string) "rocq gitlab_domain" rocq_config.gitlab_domain
    (Some "gitlab.inria.fr") ;
  check (option string) "rocq org_name" rocq_config.org_name (Some "rocq-prover") ;
  check (option string) "rocq team_name" rocq_config.team_name
    (Some "contributors") ;
  (* Verify CI config *)
  ( match rocq_config.ci_config with
  | Some ci ->
      check (option string) "rocq full_ci_variable" ci.full_ci_variable
        (Some "FULL_CI") ;
      check (option string) "rocq skip_docker_variable" ci.skip_docker_variable
        (Some "SKIP_DOCKER") ;
      check (option string) "rocq docker_path_pattern" ci.docker_path_pattern
        (Some "dev/ci/docker/.*Dockerfile.*")
  | None ->
      Alcotest.fail "Expected CI config for rocq" ) ;
  (* Verify labels config *)
  ( match rocq_config.labels with
  | Some labels ->
      check (option string) "rocq needs_rebase" labels.needs_rebase
        (Some "needs: rebase") ;
      check (option string) "rocq stale" labels.stale (Some "stale") ;
      check (option string) "rocq needs_full_ci" labels.needs_full_ci
        (Some "needs: full CI")
  | None ->
      Alcotest.fail "Expected labels config for rocq" ) ;
  (* Verify jobs config *)
  ( match rocq_config.jobs with
  | Some jobs ->
      check (option string) "rocq bench job" jobs.bench (Some "bench") ;
      ( match jobs.doc_refman with
      | Some doc_jobs ->
          check (list string) "rocq doc_refman jobs" doc_jobs
            ["doc:refman"; "doc:ci-refman"]
      | None ->
          Alcotest.fail "Expected doc_refman jobs for rocq" ) ;
      check (option string) "rocq doc_init job" jobs.doc_init (Some "doc:init") ;
      ( match jobs.doc_stdlib with
      | Some doc_jobs ->
          check (list string) "rocq doc_stdlib jobs" doc_jobs
            ["doc:stdlib"; "doc:stdlib:dune"]
      | None ->
          Alcotest.fail "Expected doc_stdlib jobs for rocq" ) ;
      check (option string) "rocq doc_ml_api job" jobs.doc_ml_api
        (Some "doc:ml-api:odoc")
  | None ->
      Alcotest.fail "Expected jobs config for rocq" ) ;
  (* Verify documentation config *)
  match rocq_config.documentation with
  | Some doc ->
      check (option string) "rocq refman_path" doc.refman_path
        (Some "_build/default/doc/refman-html/index.html") ;
      check (option string) "rocq corelib_path" doc.corelib_path
        (Some "_build/default/doc/corelib/html/index.html") ;
      check (option string) "rocq stdlib_path" doc.stdlib_path
        (Some "_build/default/doc/stdlib/html/index.html") ;
      check (option string) "rocq ml_api_path" doc.ml_api_path
        (Some "_build/default/_doc/_html/index.html")
  | None ->
      Alcotest.fail "Expected documentation config for rocq"

let test_multiple_repositories_in_table () =
  (* Test that config table correctly handles multiple repositories *)
  let config_file = "test-config.toml" in
  let toml_data = Utils.toml_of_file config_file in
  let table = repo_config_table toml_data in
  (* Verify all three repositories are in the table *)
  check bool "should have rocq config"
    (has_repo_config ~owner:"rocq-prover" ~repo:"rocq" table)
    true ;
  check bool "should have coq config"
    (has_repo_config ~owner:"coq" ~repo:"coq" table)
    true ;
  check bool "should have opam config"
    (has_repo_config ~owner:"ocaml" ~repo:"opam" table)
    true ;
  (* Verify coq/coq config *)
  let coq_config =
    Option.value_exn (get_repo_config_opt ~owner:"coq" ~repo:"coq" table)
  in
  check string "coq github_owner" coq_config.github_owner "coq" ;
  check string "coq github_repo" coq_config.github_repo "coq" ;
  check (option int) "coq installation_id" coq_config.github_installation_id
    (Some 999999) ;
  check (option string) "coq gitlab_domain" coq_config.gitlab_domain
    (Some "gitlab.com") ;
  check (option string) "coq org_name" coq_config.org_name (Some "coq") ;
  check (option string) "coq team_name" coq_config.team_name (Some "maintainers") ;
  (* Verify coq jobs config *)
  ( match coq_config.jobs with
  | Some jobs -> (
      check (option string) "coq bench job" jobs.bench (Some "benchmark") ;
      match jobs.doc_refman with
      | Some doc_jobs ->
          check (list string) "coq doc_refman jobs" doc_jobs ["doc:refman"]
      | None ->
          Alcotest.fail "Expected doc_refman jobs for coq" )
  | None ->
      Alcotest.fail "Expected jobs config for coq" ) ;
  (* Verify opam config (minimal) *)
  let opam_config =
    Option.value_exn (get_repo_config_opt ~owner:"ocaml" ~repo:"opam" table)
  in
  check string "opam github_owner" opam_config.github_owner "ocaml" ;
  check string "opam github_repo" opam_config.github_repo "opam" ;
  check (option string) "opam org_name" opam_config.org_name (Some "ocaml") ;
  check (option string) "opam team_name" opam_config.team_name None ;
  check (option string) "opam gitlab_domain" opam_config.gitlab_domain None ;
  (* Verify non-existent repository returns false *)
  check bool "should not have unknown config"
    (has_repo_config ~owner:"unknown" ~repo:"repo" table)
    false ;
  (* Verify get_repo_config_opt returns None for non-existent repo *)
  check
    (option repo_config_testable)
    "non-existent repo returns None"
    (get_repo_config_opt ~owner:"unknown" ~repo:"repo" table)
    None

let test_table_lookup_performance () =
  (* Test that table lookups work correctly for all entries *)
  let config_file = "test-config.toml" in
  let toml_data = Utils.toml_of_file config_file in
  let table = repo_config_table toml_data in
  (* Test all lookups work *)
  let rocq =
    Option.value_exn
      (get_repo_config_opt ~owner:"rocq-prover" ~repo:"rocq" table)
  in
  let coq =
    Option.value_exn (get_repo_config_opt ~owner:"coq" ~repo:"coq" table)
  in
  let opam =
    Option.value_exn (get_repo_config_opt ~owner:"ocaml" ~repo:"opam" table)
  in
  (* Verify all configs are distinct *)
  check bool "rocq and coq should be different"
    (not (String.equal rocq.github_owner coq.github_owner))
    true ;
  check bool "coq and opam should be different"
    (not (String.equal coq.github_owner opam.github_owner))
    true ;
  (* Verify table size matches expected *)
  check int "table should have 3 entries" 3 (Hashtbl.length table)

let () =
  run "Repo_config_integration"
    [ ( "file_loading"
      , [test_case "load from TOML file" `Quick test_load_from_toml_file] )
    ; ( "multiple_repositories"
      , [ test_case "multiple repositories in table" `Quick
            test_multiple_repositories_in_table
        ; test_case "table lookup performance" `Quick
            test_table_lookup_performance ] ) ]
