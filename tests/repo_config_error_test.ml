open Base
open Bot_components
open Repo_config
open Alcotest
open Repo_config_test_helpers

let test_missing_github_field () =
  let toml_str =
    {|
[repositories.rocq]
# github field is missing
gitlab_domain = "gitlab.inria.fr"
|}
  in
  let toml_data = Utils.toml_of_string toml_str in
  (* Should raise Failure with message about missing github key *)
  check_raises_failure "should raise on missing github field" (fun () ->
      parse_all_repo_configs toml_data |> ignore )

let test_invalid_github_format_no_slash () =
  let toml_str = {|
[repositories.rocq]
github = "rocq-prover-rocq"
|} in
  let toml_data = Utils.toml_of_string toml_str in
  (* Should raise Failure with message about invalid format *)
  check_raises_failure "should raise on invalid github format (no slash)"
    (fun () -> parse_all_repo_configs toml_data |> ignore )

let test_invalid_github_format_too_many_slashes () =
  let toml_str = {|
[repositories.rocq]
github = "rocq-prover/rocq/branch"
|} in
  let toml_data = Utils.toml_of_string toml_str in
  (* Should raise Failure with message about invalid format *)
  check_raises_failure
    "should raise on invalid github format (too many slashes)" (fun () ->
      parse_all_repo_configs toml_data |> ignore )

let test_invalid_github_format_empty () =
  let toml_str = {|
[repositories.rocq]
github = ""
|} in
  let toml_data = Utils.toml_of_string toml_str in
  (* Should raise Failure with message about invalid format *)
  check_raises_failure "should raise on empty github field" (fun () ->
      parse_all_repo_configs toml_data |> ignore )

let test_invalid_installation_id () =
  let toml_str =
    {|
[repositories.rocq]
github = "rocq-prover/rocq"
github_installation_id = "not-a-number"
|}
  in
  let toml_data = Utils.toml_of_string toml_str in
  (* Int.of_string will raise Failure on invalid input *)
  (* The Option.map will propagate the exception *)
  check_raises_failure "should raise on invalid installation_id" (fun () ->
      parse_all_repo_configs toml_data |> ignore )

let test_invalid_project_number () =
  let toml_str =
    {|
[repositories.rocq]
github = "rocq-prover/rocq"
github_project_number = "abc123"
|}
  in
  let toml_data = Utils.toml_of_string toml_str in
  (* Int.of_string will raise Failure on invalid input *)
  check_raises_failure "should raise on invalid project_number" (fun () ->
      parse_all_repo_configs toml_data |> ignore )

let test_repositories_section_exists_but_empty () =
  let toml_str = {|
[repositories]
# No repositories defined
|} in
  let toml_data = Utils.toml_of_string toml_str in
  let configs = parse_all_repo_configs toml_data in
  check (list repo_config_testable) "should return empty list" [] configs ;
  check int "should have zero configs" 0 (List.length configs)

let test_repositories_section_missing () =
  let toml_str = {|
[bot]
name = "testbot"
|} in
  let toml_data = Utils.toml_of_string toml_str in
  let configs = parse_all_repo_configs toml_data in
  check
    (list repo_config_testable)
    "should return empty list when no repositories section" [] configs ;
  check int "should have zero configs" 0 (List.length configs)

let test_repository_with_only_github () =
  let toml_str =
    {|
[repositories.rocq]
github = "rocq-prover/rocq"
# All other fields are optional, should parse successfully
|}
  in
  let toml_data = Utils.toml_of_string toml_str in
  let configs = parse_all_repo_configs toml_data in
  (* Should parse successfully with only github field *)
  check int "should have one config" 1 (List.length configs) ;
  let config = List.hd_exn configs in
  check string "github_owner" config.github_owner "rocq-prover" ;
  check string "github_repo" config.github_repo "rocq" ;
  check (option int) "installation_id should be None"
    config.github_installation_id None ;
  check (option string) "gitlab_domain should be None" config.gitlab_domain None

let test_repository_with_partial_config () =
  let toml_str =
    {|
[repositories.rocq]
github = "rocq-prover/rocq"
github_installation_id = "1062161"
# gitlab_domain is missing, but that's OK
org_name = "rocq-prover"
|}
  in
  let toml_data = Utils.toml_of_string toml_str in
  let configs = parse_all_repo_configs toml_data in
  (* Should parse successfully with partial config *)
  check int "should have one config" 1 (List.length configs) ;
  let config = List.hd_exn configs in
  check string "github_owner" config.github_owner "rocq-prover" ;
  check (option int) "installation_id should be Some"
    config.github_installation_id (Some 1062161) ;
  check (option string) "gitlab_domain should be None" config.gitlab_domain None ;
  check (option string) "org_name should be Some" config.org_name
    (Some "rocq-prover")

let test_known_integer_values () =
  let toml_str =
    {|
[repositories.rocq]
github = "rocq-prover/rocq"
github_installation_id = "1062161"
github_project_number = "11"
|}
  in
  let toml_data = Utils.toml_of_string toml_str in
  let configs = parse_all_repo_configs toml_data in
  check int "should have one config" 1 (List.length configs) ;
  let config = List.hd_exn configs in
  check (option int) "installation_id" config.github_installation_id
    (Some 1062161) ;
  check (option int) "project_number" config.github_project_number (Some 11)

let test_installation_id_overflow () =
  (* Test with a value that exceeds Int.max_value *)
  (* On 64-bit: max_int = 9,223,372,036,854,775,807 *)
  (* On 32-bit: max_int = 2,147,483,647 *)
  (* Use a value that definitely exceeds both: 10^20 *)
  let toml_str =
    {|
[repositories.rocq]
github = "rocq-prover/rocq"
github_installation_id = "99999999999999999999"
|}
  in
  let toml_data = Utils.toml_of_string toml_str in
  (* Int.of_string will raise Failure on overflow *)
  check_raises_failure "should raise on installation_id overflow" (fun () ->
      parse_all_repo_configs toml_data |> ignore )

let test_project_number_overflow () =
  (* Test with a value that exceeds Int.max_value *)
  let toml_str =
    {|
[repositories.rocq]
github = "rocq-prover/rocq"
github_project_number = "99999999999999999999"
|}
  in
  let toml_data = Utils.toml_of_string toml_str in
  (* Int.of_string will raise Failure on overflow *)
  check_raises_failure "should raise on project_number overflow" (fun () ->
      parse_all_repo_configs toml_data |> ignore )

let () =
  run "Repo_config_error"
    [ ( "error_handling"
      , [ test_case "missing github field" `Quick test_missing_github_field
        ; test_case "invalid github format (no slash)" `Quick
            test_invalid_github_format_no_slash
        ; test_case "invalid github format (too many slashes)" `Quick
            test_invalid_github_format_too_many_slashes
        ; test_case "invalid github format (empty)" `Quick
            test_invalid_github_format_empty
        ; test_case "invalid installation_id" `Quick
            test_invalid_installation_id
        ; test_case "invalid project_number" `Quick test_invalid_project_number
        ] )
    ; ( "edge_cases"
      , [ test_case "repositories section exists but empty" `Quick
            test_repositories_section_exists_but_empty
        ; test_case "repositories section missing" `Quick
            test_repositories_section_missing
        ; test_case "repository with only github" `Quick
            test_repository_with_only_github
        ; test_case "repository with partial config" `Quick
            test_repository_with_partial_config ] )
    ; ( "integer_parsing"
      , [ test_case "known integer values" `Quick test_known_integer_values
        ; test_case "installation_id overflow" `Quick
            test_installation_id_overflow
        ; test_case "project_number overflow" `Quick
            test_project_number_overflow ] ) ]
