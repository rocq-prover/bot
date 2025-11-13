open Base
open Alcotest
open Bot_components.Utils
open Config

(** Test API timeout configuration parsing and priority *)

let float_testable = testable Float.pp Float.equal

let test_timeout_from_toml () =
  let toml_str = {|
[bot]
api_timeout = "10.0"
|} in
  let toml_data = toml_of_string toml_str in
  let timeout = api_timeout toml_data in
  check float_testable "timeout from TOML" timeout 10.0

let test_timeout_from_env_var () =
  let original_env = Sys.getenv "API_TIMEOUT" in
  (* Set env var for this test *)
  Unix.putenv "API_TIMEOUT" "7.5" ;
  let toml_str = {|
[bot]
name = "testbot"
|} in
  let toml_data = toml_of_string toml_str in
  let timeout = api_timeout toml_data in
  check float_testable "timeout from env var" timeout 7.5 ;
  (* Restore original env var *)
  match original_env with
  | Some value ->
      Unix.putenv "API_TIMEOUT" value
  | None ->
      ()

let test_timeout_default () =
  (* Test that default value (5.0) is used when neither TOML nor env var is set *)
  let original_env = Sys.getenv "API_TIMEOUT" in
  let toml_str = {|
[bot]
name = "testbot"
|} in
  let toml_data = toml_of_string toml_str in
  match original_env with
  | None ->
      (* Env var not set - should use default 5.0 *)
      let timeout = api_timeout toml_data in
      check float_testable "timeout default is 5.0 when not configured" timeout
        5.0
  | Some _ ->
      (* Env var is set - cannot test default without unsetting it.
         Skip this test case when env var is already configured. *)
      Alcotest.skip ()

let test_timeout_priority_toml_over_env () =
  let original_env = Sys.getenv "API_TIMEOUT" in
  Unix.putenv "API_TIMEOUT" "99.0" ;
  let toml_str = {|
[bot]
api_timeout = "3.0"
|} in
  let toml_data = toml_of_string toml_str in
  let timeout = api_timeout toml_data in
  check float_testable "TOML takes priority over env var" timeout 3.0 ;
  (* Restore original env var *)
  match original_env with
  | Some value ->
      Unix.putenv "API_TIMEOUT" value
  | None ->
      ()

let () =
  run "Config Timeout"
    [ ( "timeout"
      , [ test_case "timeout from TOML" `Quick test_timeout_from_toml
        ; test_case "timeout from env var" `Quick test_timeout_from_env_var
        ; test_case "timeout default" `Quick test_timeout_default
        ; test_case "TOML priority over env var" `Quick
            test_timeout_priority_toml_over_env ] ) ]
