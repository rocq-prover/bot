open Base
open Repo_config
open Alcotest
open Refactored_code_test_helpers

(** Tests for bench job detection (actions/job.ml) *)

let test_bench_job_detection_enabled () =
  (* Test that bench job is detected when configured *)
  let table =
    create_generic_config ~owner:"test-org" ~repo:"test-repo" ~bench_job:"bench"
      ()
  in
  match get_repo_config_opt ~owner:"test-org" ~repo:"test-repo" table with
  | Some config -> (
    match config.jobs with
    | Some jobs ->
        check (option string) "bench job configured" jobs.bench (Some "bench") ;
        (* Verify job name matching logic *)
        let is_bench =
          match jobs.bench with
          | Some bench_name ->
              String.equal "bench" bench_name
          | None ->
              false
        in
        check bool "bench job matches" is_bench true
    | None ->
        fail "Expected jobs config for bench test" )
  | None ->
      fail "Expected config for bench test"

let test_bench_job_detection_disabled () =
  (* Test that bench job is not detected when not configured *)
  let table = create_generic_config ~owner:"test-org" ~repo:"test-repo" () in
  match get_repo_config_opt ~owner:"test-org" ~repo:"test-repo" table with
  | Some config -> (
    match config.jobs with
    | Some jobs ->
        check (option string) "bench job not configured" jobs.bench None
    | None ->
        () )
  | None ->
      fail "Expected config for bench test"

let test_rocq_bench_job_still_works () =
  (* Test that rocq bench job still works *)
  let table = create_rocq_config () in
  match get_repo_config_opt ~owner:"rocq-prover" ~repo:"rocq" table with
  | Some config -> (
    match config.jobs with
    | Some jobs ->
        check (option string) "rocq bench job configured" jobs.bench
          (Some "bench") ;
        (* Verify job name matching *)
        let is_bench =
          match jobs.bench with
          | Some bench_name ->
              String.equal "bench" bench_name
          | None ->
              false
        in
        check bool "rocq bench job matches" is_bench true
    | None ->
        fail "Expected jobs config for rocq bench test" )
  | None ->
      fail "Expected rocq config for bench test"

let () =
  run "Refactored Code - Jobs"
    [ ( "bench_job"
      , [ test_case "bench job detection enabled" `Quick
            test_bench_job_detection_enabled
        ; test_case "bench job detection disabled" `Quick
            test_bench_job_detection_disabled
        ; test_case "rocq bench job still works" `Quick
            test_rocq_bench_job_still_works ] ) ]
