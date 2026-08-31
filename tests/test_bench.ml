open Alcotest
open Bench

let rocq_domain = Some "gitlab.inria.fr"

let rocq_owner = Some "coq"

let rocq_repo = Some "coq"

let test_gitlab_job_url_full () =
  (check (option string))
    "rocq job url" (Some "https://gitlab.inria.fr/coq/coq/-/jobs/42")
    (gitlab_job_url ~gitlab_domain:rocq_domain ~gitlab_owner:rocq_owner
       ~gitlab_repo:rocq_repo ~job_id:42 )

let test_gitlab_job_url_missing () =
  (check (option string))
    "missing domain" None
    (gitlab_job_url ~gitlab_domain:None ~gitlab_owner:rocq_owner
       ~gitlab_repo:rocq_repo ~job_id:1 ) ;
  (check (option string))
    "missing owner" None
    (gitlab_job_url ~gitlab_domain:rocq_domain ~gitlab_owner:None
       ~gitlab_repo:rocq_repo ~job_id:1 ) ;
  (check (option string))
    "missing repo" None
    (gitlab_job_url ~gitlab_domain:rocq_domain ~gitlab_owner:rocq_owner
       ~gitlab_repo:None ~job_id:1 )

let test_bench_summary_prefix () =
  (check (option string))
    "link prefix" (Some "[bench](https://gitlab.inria.fr/coq/coq/-/jobs/")
    (bench_summary_job_link_prefix ~gitlab_domain:rocq_domain
       ~gitlab_owner:rocq_owner ~gitlab_repo:rocq_repo ~job_name:"bench" )

let test_bench_summary_regex () =
  let summary =
    "Pipeline summary with \
     [bench](https://gitlab.inria.fr/coq/coq/-/jobs/12345) and GitLab Project \
     ID: 999"
  in
  match
    bench_summary_build_id_regex ~gitlab_domain:rocq_domain
      ~gitlab_owner:rocq_owner ~gitlab_repo:rocq_repo ~job_name:"bench"
  with
  | None ->
      fail "expected regex"
  | Some regexp ->
      if String_utils.string_match ~regexp summary then
        check string "build id" "12345" (Str.matched_group 1 summary)
      else fail "regex did not match summary"

let test_bench_summary_regex_missing () =
  (check (option string))
    "missing coords" None
    (bench_summary_build_id_regex ~gitlab_domain:None ~gitlab_owner:rocq_owner
       ~gitlab_repo:rocq_repo ~job_name:"bench" )

let () =
  run "Bench tests"
    [ ( "gitlab urls"
      , [ ("job url full", `Quick, test_gitlab_job_url_full)
        ; ("job url missing", `Quick, test_gitlab_job_url_missing)
        ; ("summary prefix", `Quick, test_bench_summary_prefix)
        ; ("summary regex", `Quick, test_bench_summary_regex)
        ; ("summary regex missing", `Quick, test_bench_summary_regex_missing) ]
      ) ]
