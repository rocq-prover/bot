open Base
open Repo_config
open Alcotest
open Refactored_code_test_helpers
open Bot_components.Utils

(** Tests for generic repos and rocq backward compatibility *)

let test_generic_repo_no_hardcoded_checks () =
  (* Test that any repo works with config, not just rocq *)
  let test_repos =
    [ ("test-org", "test-repo")
    ; ("coq", "coq")
    ; ("math-comp", "math-comp")
    ; ("ocaml", "opam")
    ; ("random-org", "random-repo") ]
  in
  List.iter test_repos ~f:(fun (owner, repo) ->
      let table =
        create_generic_config ~owner ~repo ~gitlab_domain:"gitlab.com" ()
      in
      (* All repos should work with same generic logic *)
      check bool
        (f "repo %s/%s should have config" owner repo)
        (has_repo_config ~owner ~repo table)
        true ;
      (* All repos should be treated equally - no special cases *)
      match get_repo_config_opt ~owner ~repo table with
      | Some config ->
          check string (f "%s/%s owner" owner repo) config.github_owner owner ;
          check string (f "%s/%s repo" owner repo) config.github_repo repo ;
          check (option string)
            (f "%s/%s gitlab_domain" owner repo)
            config.gitlab_domain (Some "gitlab.com")
      | None ->
          fail (f "Expected config for %s/%s" owner repo) )

let test_rocq_config_backward_compatibility () =
  let table = create_rocq_config () in
  let owner = "rocq-prover" in
  let repo = "rocq" in
  (* Verify rocq config exists *)
  check bool "rocq should have config" (has_repo_config ~owner ~repo table) true ;
  match get_repo_config_opt ~owner ~repo table with
  | Some config -> (
      (* Verify all rocq-specific values are preserved *)
      check string "rocq owner" config.github_owner owner ;
      check string "rocq repo" config.github_repo repo ;
      check (option int) "rocq installation_id" config.github_installation_id
        (Some 1062161) ;
      check (option int) "rocq project_number" config.github_project_number
        (Some 11) ;
      check (option string) "rocq gitlab_domain" config.gitlab_domain
        (Some "gitlab.inria.fr") ;
      check (option string) "rocq gitlab_owner" config.gitlab_owner (Some "coq") ;
      check (option string) "rocq gitlab_repo" config.gitlab_repo (Some "coq") ;
      check (option string) "rocq org_name" config.org_name (Some "rocq-prover") ;
      check (option string) "rocq team_name" config.team_name
        (Some "contributors") ;
      (* Verify CI config *)
      ( match config.ci_config with
      | Some ci ->
          check (option string) "rocq full_ci_variable" ci.full_ci_variable
            (Some "FULL_CI") ;
          check (option string) "rocq skip_docker_variable"
            ci.skip_docker_variable (Some "SKIP_DOCKER") ;
          check (option string) "rocq docker_path_pattern"
            ci.docker_path_pattern (Some "dev/ci/docker/.*Dockerfile.*")
      | None ->
          fail "Expected CI config for rocq" ) ;
      (* Verify labels config *)
      ( match config.labels with
      | Some labels ->
          check (option string) "rocq needs_rebase" labels.needs_rebase
            (Some "needs: rebase") ;
          check (option string) "rocq stale" labels.stale (Some "stale") ;
          check (option string) "rocq needs_full_ci" labels.needs_full_ci
            (Some "needs: full CI") ;
          check (option string) "rocq request_full_ci" labels.request_full_ci
            (Some "request: full CI") ;
          check (option string) "rocq needs_independent_fix"
            labels.needs_independent_fix (Some "needs: independent fix")
      | None ->
          fail "Expected labels config for rocq" ) ;
      (* Verify jobs config *)
      ( match config.jobs with
      | Some jobs ->
          check (option string) "rocq bench job" jobs.bench (Some "bench") ;
          check
            (option (list string))
            "rocq doc_refman" jobs.doc_refman
            (Some ["doc:refman"; "doc:ci-refman"]) ;
          check (option string) "rocq doc_init" jobs.doc_init (Some "doc:init") ;
          check
            (option (list string))
            "rocq doc_stdlib" jobs.doc_stdlib
            (Some ["doc:stdlib"; "doc:stdlib:dune"]) ;
          check (option string) "rocq doc_ml_api" jobs.doc_ml_api
            (Some "doc:ml-api:odoc")
      | None ->
          fail "Expected jobs config for rocq" ) ;
      (* Verify documentation config *)
      match config.documentation with
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
          fail "Expected documentation config for rocq" )
  | None ->
      fail "Expected rocq config to exist"

let () =
  run "Refactored Code - Generic"
    [ ( "generic_repos"
      , [ test_case "generic repos work without hardcoded checks" `Quick
            test_generic_repo_no_hardcoded_checks ] )
    ; ( "rocq_compatibility"
      , [ test_case "rocq config backward compatibility" `Quick
            test_rocq_config_backward_compatibility ] ) ]
