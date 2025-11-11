open Base
open Bot_components
open Repo_config
open QCheck_alcotest
open QCheck2

(* Property-based tests for integer parsing in repo_config *)

let prop_parse_valid_installation_id n =
  (* Test that any valid integer can be parsed as installation_id *)
  let n_str = Int.to_string n in
  let toml_str =
    Printf.sprintf
      {|
[repositories.rocq]
github = "rocq-prover/rocq"
github_installation_id = "%s"
|}
      n_str
  in
  let toml_data = Utils.toml_of_string toml_str in
  let configs = parse_all_repo_configs toml_data in
  let config = List.hd_exn configs in
  Option.equal Int.equal config.github_installation_id (Some n)

let prop_parse_valid_project_number n =
  (* Test that any valid integer can be parsed as project_number *)
  let n_str = Int.to_string n in
  let toml_str =
    Printf.sprintf
      {|
[repositories.rocq]
github = "rocq-prover/rocq"
github_project_number = "%s"
|}
      n_str
  in
  let toml_data = Utils.toml_of_string toml_str in
  let configs = parse_all_repo_configs toml_data in
  let config = List.hd_exn configs in
  Option.equal Int.equal config.github_project_number (Some n)

let prop_parse_both_integers n1 n2 =
  (* Test that both integers can be parsed together *)
  let n1_str = Int.to_string n1 in
  let n2_str = Int.to_string n2 in
  let toml_str =
    Printf.sprintf
      {|
[repositories.rocq]
github = "rocq-prover/rocq"
github_installation_id = "%s"
github_project_number = "%s"
|}
      n1_str n2_str
  in
  let toml_data = Utils.toml_of_string toml_str in
  let configs = parse_all_repo_configs toml_data in
  let config = List.hd_exn configs in
  Option.equal Int.equal config.github_installation_id (Some n1)
  && Option.equal Int.equal config.github_project_number (Some n2)

let prop_parse_boundary_values n =
  (* Test boundary values: Int.max_value, Int.min_value, 0, -1, 1 *)
  let n_str = Int.to_string n in
  let toml_str =
    Printf.sprintf
      {|
[repositories.rocq]
github = "rocq-prover/rocq"
github_installation_id = "%s"
github_project_number = "%s"
|}
      n_str n_str
  in
  let toml_data = Utils.toml_of_string toml_str in
  let configs = parse_all_repo_configs toml_data in
  let config = List.hd_exn configs in
  Option.equal Int.equal config.github_installation_id (Some n)
  && Option.equal Int.equal config.github_project_number (Some n)

let () =
  Alcotest.run "Repo_config_property"
    [ ( "integer_parsing"
      , [ to_alcotest
            (Test.make ~count:1000
               Gen.(int_range (-1000) 1000)
               prop_parse_valid_installation_id )
        ; to_alcotest
            (Test.make ~count:1000
               Gen.(int_range (-1000) 1000)
               prop_parse_valid_project_number )
        ; to_alcotest
            (Test.make ~count:500
               Gen.(pair (int_range (-1000) 1000) (int_range (-1000) 1000))
               (fun (n1, n2) -> prop_parse_both_integers n1 n2) )
        ; to_alcotest
            (Test.make ~count:10
               Gen.(
                 oneof
                   [ pure Int.max_value
                   ; pure Int.min_value
                   ; pure 0
                   ; pure (-1)
                   ; pure 1
                   ; int_range (Int.max_value - 10) Int.max_value
                   ; int_range Int.min_value (Int.min_value + 10) ] )
               prop_parse_boundary_values ) ] ) ]
