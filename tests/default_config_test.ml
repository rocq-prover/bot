open Base
open Alcotest
open Bot_components.Utils

let test_defaults_for_any_repo () =
  let owner = "test-org" in
  let repo = "test-repo" in
  let defaults = Default.get_defaults ~owner ~repo in
  check string "github_owner" defaults.github_owner owner ;
  check string "github_repo" defaults.github_repo repo ;
  check (option string) "gitlab_domain" defaults.gitlab_domain
    (Some "gitlab.com") ;
  check (option string) "org_name" defaults.org_name (Some owner) ;
  check (option string) "team_name" defaults.team_name (Some "maintainers") ;
  ( match defaults.ci_config with
  | Some ci ->
      check (option string) "full_ci_variable" ci.full_ci_variable
        (Some "FULL_CI") ;
      check (option string) "skip_docker_variable" ci.skip_docker_variable
        (Some "SKIP_DOCKER")
  | None ->
      fail "Expected CI config defaults" ) ;
  match defaults.labels with
  | Some labels ->
      check (option string) "needs_rebase" labels.needs_rebase
        (Some "needs: rebase") ;
      check (option string) "stale" labels.stale (Some "stale")
  | None ->
      fail "Expected labels defaults"

let test_defaults_no_hardcoded_patterns () =
  let repos =
    ["rocq-prover/rocq"; "coq/coq"; "math-comp/math-comp"; "ocaml/opam"]
  in
  List.iter repos ~f:(fun repo_full ->
      match String.split ~on:'/' repo_full with
      | [owner; repo] ->
          let defaults = Default.get_defaults ~owner ~repo in
          check string "owner matches" defaults.github_owner owner ;
          check string "repo matches" defaults.github_repo repo ;
          check (option string) "gitlab_domain is generic"
            defaults.gitlab_domain (Some "gitlab.com")
      | _ ->
          fail (f "Invalid repo format: %s" repo_full) )

let () =
  run "Defaults"
    [ ( "defaults"
      , [test_case "defaults for any repo" `Quick test_defaults_for_any_repo] )
    ; ( "no_hardcoded_patterns"
      , [ test_case "defaults for any repo" `Quick
            test_defaults_no_hardcoded_patterns ] ) ]
