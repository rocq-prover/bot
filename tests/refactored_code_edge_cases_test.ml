open Base
open Repo_config
open Alcotest
open Test_helpers
open Bot_components.Utils

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

let test_empty_table () =
  (* Test that empty table works *)
  let table = create_repo_config_table (toml_of_string "") in
  check int "empty table size" (Hashtbl.length table) 0 ;
  check bool "empty table lookup"
    (has_repo_config ~owner:"any" ~repo:"any" table)
    false

let test_case_sensitivity () =
  (* Test that owner/repo names are case-sensitive *)
  let toml_str = {|
[repositories.test]
github = "Test-Org/Test-Repo"
|} in
  let table = create_repo_config_table (toml_of_string toml_str) in
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
      , [test_case "missing config handling" `Quick test_missing_config_handling]
      )
    ; ( "edge_cases"
      , [ test_case "empty table" `Quick test_empty_table
        ; test_case "case sensitivity" `Quick test_case_sensitivity ] ) ]
