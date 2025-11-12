open Base
open Repo_config
open Alcotest
open Repo_config_test_helpers
open Refactored_code_test_helpers
open Bot_components.Utils

(** Tests for missing config, multiple repos, and edge cases *)

let test_missing_config_handling () =
  (* Test that missing configs are handled gracefully *)
  let table = create_repo_config_table (toml_of_string "") in
  let owner = "nonexistent-org" in
  let repo = "nonexistent-repo" in
  (* Should not have config *)
  check bool "missing config" (has_repo_config ~owner ~repo table) false ;
  (* Should return None *)
  check
    (option repo_config_testable)
    "missing config returns None"
    (get_repo_config_opt ~owner ~repo table)
    None

let test_partial_config_handling () =
  (* Test that partial configs work (some fields missing) *)
  let table =
    create_generic_config ~owner:"test-org" ~repo:"test-repo"
      ~gitlab_domain:"gitlab.com" ()
  in
  match get_repo_config_opt ~owner:"test-org" ~repo:"test-repo" table with
  | Some config ->
      (* Should have gitlab_domain but not org_name/team_name *)
      check (option string) "partial gitlab_domain" config.gitlab_domain
        (Some "gitlab.com") ;
      check (option string) "partial org_name" config.org_name None ;
      check (option string) "partial team_name" config.team_name None
  | None ->
      fail "Expected config for partial test"

let test_multiple_repos_no_interference () =
  (* Test that multiple repos work independently *)
  let toml_str =
    {|
[repositories.repo1]
github = "org1/repo1"
gitlab_domain = "gitlab.com"

[repositories.repo2]
github = "org2/repo2"
gitlab_domain = "gitlab.inria.fr"

[repositories.repo3]
github = "org3/repo3"
gitlab_domain = "gitlab.example.com"
|}
  in
  let toml_data = toml_of_string toml_str in
  let table = create_repo_config_table toml_data in
  (* Each repo should have its own config *)
  check bool "repo1 has config"
    (has_repo_config ~owner:"org1" ~repo:"repo1" table)
    true ;
  check bool "repo2 has config"
    (has_repo_config ~owner:"org2" ~repo:"repo2" table)
    true ;
  check bool "repo3 has config"
    (has_repo_config ~owner:"org3" ~repo:"repo3" table)
    true ;
  (* Each repo should have different gitlab_domain *)
  ( match get_repo_config_opt ~owner:"org1" ~repo:"repo1" table with
  | Some config ->
      check (option string) "repo1 gitlab_domain" config.gitlab_domain
        (Some "gitlab.com")
  | None ->
      fail "Expected repo1 config" ) ;
  ( match get_repo_config_opt ~owner:"org2" ~repo:"repo2" table with
  | Some config ->
      check (option string) "repo2 gitlab_domain" config.gitlab_domain
        (Some "gitlab.inria.fr")
  | None ->
      fail "Expected repo2 config" ) ;
  match get_repo_config_opt ~owner:"org3" ~repo:"repo3" table with
  | Some config ->
      check (option string) "repo3 gitlab_domain" config.gitlab_domain
        (Some "gitlab.example.com")
  | None ->
      fail "Expected repo3 config"

let test_empty_table () =
  (* Test that empty table works *)
  let table = create_repo_config_table (toml_of_string "") in
  check int "empty table size" (Hashtbl.length table) 0 ;
  check bool "empty table lookup"
    (has_repo_config ~owner:"any" ~repo:"any" table)
    false

let test_special_characters_in_names () =
  (* Test that special characters in repo names work *)
  let table =
    create_generic_config ~owner:"test-org" ~repo:"test-repo-123" ()
  in
  check bool "special chars in repo name"
    (has_repo_config ~owner:"test-org" ~repo:"test-repo-123" table)
    true

let test_case_sensitivity () =
  (* Test that owner/repo names are case-sensitive *)
  let table = create_generic_config ~owner:"Test-Org" ~repo:"Test-Repo" () in
  (* Exact match should work *)
  check bool "case-sensitive exact match"
    (has_repo_config ~owner:"Test-Org" ~repo:"Test-Repo" table)
    true ;
  (* Different case should not match *)
  check bool "case-sensitive different case"
    (has_repo_config ~owner:"test-org" ~repo:"test-repo" table)
    false

let () =
  run "Refactored Code - Edge Cases"
    [ ( "missing_config"
      , [ test_case "missing config handling" `Quick test_missing_config_handling
        ; test_case "partial config handling" `Quick
            test_partial_config_handling ] )
    ; ( "multiple_repos"
      , [ test_case "multiple repos no interference" `Quick
            test_multiple_repos_no_interference ] )
    ; ( "edge_cases"
      , [ test_case "empty table" `Quick test_empty_table
        ; test_case "special characters in names" `Quick
            test_special_characters_in_names
        ; test_case "case sensitivity" `Quick test_case_sensitivity ] ) ]
