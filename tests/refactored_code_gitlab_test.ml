open Base
open Repo_config
open Bot_components.Utils
open Alcotest
open Refactored_code_test_helpers

(** Tests for GitLab domain configuration (webhooks/github.ml, webhooks/gitlab.ml) *)

let test_gitlab_domain_configuration () =
  (* Test that GitLab domain is configurable (not hardcoded) *)
  let table = create_rocq_config () in
  match get_repo_config_opt ~owner:"rocq-prover" ~repo:"rocq" table with
  | Some config ->
      (* Rocq uses gitlab.inria.fr (not hardcoded) *)
      check (option string) "rocq gitlab_domain" config.gitlab_domain
        (Some "gitlab.inria.fr") ;
      check (option string) "rocq gitlab_owner" config.gitlab_owner (Some "coq") ;
      check (option string) "rocq gitlab_repo" config.gitlab_repo (Some "coq")
  | None ->
      fail "Expected rocq config for gitlab domain test"

let test_generic_gitlab_domain () =
  (* Test that generic repos can use any GitLab domain *)
  let test_domains = ["gitlab.com"; "gitlab.inria.fr"; "gitlab.example.com"] in
  List.iter test_domains ~f:(fun domain ->
      let table =
        create_generic_config ~owner:"test-org" ~repo:"test-repo"
          ~gitlab_domain:domain ()
      in
      match get_repo_config_opt ~owner:"test-org" ~repo:"test-repo" table with
      | Some config ->
          check (option string)
            (f "gitlab_domain %s" domain)
            config.gitlab_domain (Some domain)
      | None ->
          fail (f "Expected config for domain %s" domain) )

let () =
  run "Refactored Code - GitLab"
    [ ( "gitlab_domain"
      , [ test_case "gitlab domain configuration" `Quick
            test_gitlab_domain_configuration
        ; test_case "generic gitlab domain" `Quick test_generic_gitlab_domain ]
      ) ]
