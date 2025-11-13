open Base
open Repo_config
open Alcotest
open Refactored_code_test_helpers
open Job_status

(** Tests for custom job status handling (merged from job_status_rocq) *)

let custom_job_info_testable =
  let pp fmt info =
    Stdlib.Format.fprintf fmt
      "{docker_image=%s; dependencies=[%s]; targets=[%s]; compiler=%s; \
       opam_variant=%s}"
      info.docker_image
      (String.concat ~sep:", " info.dependencies)
      (String.concat ~sep:", " info.targets)
      info.compiler info.opam_variant
  in
  let equal a b =
    String.equal a.docker_image b.docker_image
    && List.equal String.equal a.dependencies b.dependencies
    && List.equal String.equal a.targets b.targets
    && String.equal a.compiler b.compiler
    && String.equal a.opam_variant b.opam_variant
  in
  testable pp equal

let test_custom_job_status_enabled () =
  (* Test that custom job status handling works when enabled in config *)
  (* Add custom_job_status flag to config *)
  let toml_str =
    {|
[repositories.test]
github = "test-org/test-repo"

[repositories.test.jobs]
custom_job_status = true
|}
  in
  let toml_data = Bot_components.Utils.toml_of_string toml_str in
  let table = create_repo_config_table toml_data in
  match get_repo_config_opt ~owner:"test-org" ~repo:"test-repo" table with
  | Some config -> (
    match config.jobs with
    | Some jobs ->
        check bool "custom_job_status enabled"
          (Option.value ~default:false jobs.custom_job_status)
          true
    | None ->
        fail "Expected jobs config" )
  | None ->
      fail "Expected config for custom job status test"

let test_custom_job_status_disabled () =
  (* Test that custom job status handling is disabled when not configured *)
  let table = create_generic_config ~owner:"test-org" ~repo:"test-repo" () in
  match get_repo_config_opt ~owner:"test-org" ~repo:"test-repo" table with
  | Some config -> (
    match config.jobs with
    | Some jobs ->
        check bool "custom_job_status disabled"
          (Option.value ~default:false jobs.custom_job_status)
          false
    | None ->
        (* No jobs config - custom_job_status should be disabled *)
        Alcotest.skip () )
  | None ->
      Alcotest.skip ()

let test_extract_custom_job_info () =
  (* Test that extract_custom_job_info correctly parses trace lines *)
  let trace_lines =
    [ "Using Docker executor with image coqorg/coq:dev"
    ; "CI_TARGETS = all"
    ; "COMPILER=4.14.0"
    ; "OPAM_VARIANT=+default"
    ; "Downloading artifacts for job1"
    ; "Downloading artifacts for job2" ]
  in
  match extract_custom_job_info trace_lines with
  | Some info ->
      check string "docker_image" info.docker_image "coqorg/coq:dev" ;
      check (list string) "dependencies" info.dependencies ["job1"; "job2"] ;
      check (list string) "targets" info.targets ["all"] ;
      check string "compiler" info.compiler "4.14.0" ;
      check string "opam_variant" info.opam_variant "+default"
  | None ->
      fail "Expected to extract job info from trace lines"

let test_extract_custom_job_info_missing_fields () =
  (* Test that extract_custom_job_info returns None when required fields are missing *)
  let trace_lines = ["Some random log line"] in
  check
    (option custom_job_info_testable)
    "missing fields returns None"
    (extract_custom_job_info trace_lines)
    None

let test_build_custom_summary_tail () =
  (* Test that build_custom_summary_tail creates correct summary *)
  let job_info =
    Some
      { docker_image= "coqorg/coq:dev"
      ; dependencies= ["job1"; "job2"]
      ; targets= ["all"]
      ; compiler= "4.14.0"
      ; opam_variant= "+default" }
  in
  let trace_description = "Test trace description" in
  let summary = build_custom_summary_tail job_info ~trace_description in
  check bool "summary contains docker_image"
    (String.is_substring summary ~substring:"coqorg/coq:dev")
    true ;
  check bool "summary contains compiler"
    (String.is_substring summary ~substring:"4.14.0")
    true ;
  check bool "summary contains dependencies"
    (String.is_substring summary ~substring:"job1")
    true ;
  check bool "summary contains targets"
    (String.is_substring summary ~substring:"all")
    true ;
  check bool "summary contains trace_description"
    (String.is_substring summary ~substring:trace_description)
    true

let test_build_custom_summary_tail_none () =
  (* Test that build_custom_summary_tail returns trace_description when job_info is None *)
  let trace_description = "Test trace description" in
  let summary = build_custom_summary_tail None ~trace_description in
  check string "summary equals trace_description" summary trace_description

let test_custom_summary_builder () =
  (* Test that custom_summary_builder returns a function that builds summaries *)
  let trace_lines =
    [ "Using Docker executor with image coqorg/coq:dev"
    ; "CI_TARGETS = all"
    ; "COMPILER=4.14.0"
    ; "OPAM_VARIANT=+default" ]
  in
  let builder_fn = custom_summary_builder trace_lines in
  let trace_description = "Test description" in
  let summary = Lwt_main.run (builder_fn trace_description) in
  check bool "summary contains docker_image"
    (String.is_substring summary ~substring:"coqorg/coq:dev")
    true ;
  check bool "summary contains trace_description"
    (String.is_substring summary ~substring:trace_description)
    true

let test_rocq_custom_job_status_still_works () =
  (* Test that rocq can still use custom job status via config *)
  let toml_str =
    {|
[repositories.rocq]
github = "rocq-prover/rocq"

[repositories.rocq.jobs]
custom_job_status = true
bench = "bench"
|}
  in
  let toml_data = Bot_components.Utils.toml_of_string toml_str in
  let table = create_repo_config_table toml_data in
  match get_repo_config_opt ~owner:"rocq-prover" ~repo:"rocq" table with
  | Some config -> (
    match config.jobs with
    | Some jobs ->
        check bool "rocq custom_job_status enabled"
          (Option.value ~default:false jobs.custom_job_status)
          true ;
        check (option string) "rocq bench job" jobs.bench (Some "bench")
    | None ->
        fail "Expected jobs config for rocq" )
  | None ->
      fail "Expected rocq config"

let () =
  run "Job Status - Custom Handling"
    [ ( "config"
      , [ test_case "custom job status enabled" `Quick
            test_custom_job_status_enabled
        ; test_case "custom job status disabled" `Quick
            test_custom_job_status_disabled
        ; test_case "rocq custom job status still works" `Quick
            test_rocq_custom_job_status_still_works ] )
    ; ( "extraction"
      , [ test_case "extract custom job info" `Quick test_extract_custom_job_info
        ; test_case "extract custom job info missing fields" `Quick
            test_extract_custom_job_info_missing_fields ] )
    ; ( "summary"
      , [ test_case "build custom summary tail" `Quick
            test_build_custom_summary_tail
        ; test_case "build custom summary tail none" `Quick
            test_build_custom_summary_tail_none
        ; test_case "custom summary builder" `Quick test_custom_summary_builder
        ] ) ]
