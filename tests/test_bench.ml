open Base
open Alcotest

let parse s = Repo_config.make_repo_config_table (Utils.toml_of_string s)

let cfg_full =
  Option.value_exn
    (Repo_config.find_by_github ~owner:"rocq-prover" ~repo:"rocq"
       (parse
          {|
    [repositories.rocq]
    github = "rocq-prover/rocq"
    gitlab_domain = "gitlab.inria.fr"
    gitlab_owner = "coq"
    gitlab_repo = "coq"

    [repositories.rocq.jobs]
    bench_job = "bench"
    |} ) )

let cfg_missing_gitlab =
  Option.value_exn
    (Repo_config.find_by_github ~owner:"my-org" ~repo:"my-repo"
       (parse
          {|
    [repositories.demo]
    github = "my-org/my-repo"

    [repositories.demo.jobs]
    bench_job = "bench"
    |} ) )

let job_link_prefix (cfg : Repo_config.t) ~job_name =
  match (cfg.gitlab_domain, cfg.gitlab_owner, cfg.gitlab_repo) with
  | Some domain, Some owner, Some repo ->
      Some
        (Printf.sprintf "[%s](https://%s/%s/%s/-/jobs/" job_name domain owner
           repo )
  | _ ->
      None

let build_id_regex cfg ~job_name =
  Option.map (job_link_prefix cfg ~job_name) ~f:(fun prefix ->
      Printf.sprintf {|.*%s\([0-9]*\)|} (Str.quote prefix) )

let test_gitlab_job_url_full () =
  (check (option string))
    "rocq job url" (Some "https://gitlab.inria.fr/coq/coq/-/jobs/42")
    (Repo_config.gitlab_job_url cfg_full ~job_id:42)

let test_gitlab_job_url_missing () =
  (check (option string))
    "missing gitlab coords" None
    (Repo_config.gitlab_job_url cfg_missing_gitlab ~job_id:1)

let test_bench_summary_prefix () =
  (check (option string))
    "link prefix" (Some "[bench](https://gitlab.inria.fr/coq/coq/-/jobs/")
    (job_link_prefix cfg_full ~job_name:"bench")

let test_bench_summary_regex () =
  let summary =
    "Pipeline summary with \
     [bench](https://gitlab.inria.fr/coq/coq/-/jobs/12345) and GitLab Project \
     ID: 999"
  in
  match build_id_regex cfg_full ~job_name:"bench" with
  | None ->
      fail "expected regex"
  | Some regexp ->
      if String_utils.string_match ~regexp summary then
        check string "build id" "12345" (Str.matched_group 1 summary)
      else fail "regex did not match summary"

let test_bench_summary_regex_missing () =
  (check (option string))
    "missing coords" None
    (build_id_regex cfg_missing_gitlab ~job_name:"bench")

let test_pages_artifact_url () =
  (check (option string))
    "pages url"
    (Some
       "https://coq.gitlabpages.inria.fr/-/coq/-/jobs/42/artifacts/_bench/timings/bench_summary"
    )
    (Repo_config.gitlab_pages_artifact_url cfg_full ~job_id:42
       ~artifact:"_bench/timings/bench_summary" ) ;
  (check (option string))
    "pages url missing" None
    (Repo_config.gitlab_pages_artifact_url cfg_missing_gitlab ~job_id:42
       ~artifact:"_bench/timings/bench_summary" )

let () =
  run "Bench tests"
    [ ( "gitlab urls"
      , [ ("job url full", `Quick, test_gitlab_job_url_full)
        ; ("job url missing", `Quick, test_gitlab_job_url_missing)
        ; ("summary prefix", `Quick, test_bench_summary_prefix)
        ; ("summary regex", `Quick, test_bench_summary_regex)
        ; ("summary regex missing", `Quick, test_bench_summary_regex_missing)
        ; ("pages artifact url", `Quick, test_pages_artifact_url) ] ) ]
