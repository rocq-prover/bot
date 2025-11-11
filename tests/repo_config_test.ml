open Base
open Bot_components
open Repo_config
open Alcotest

(** Helper to create a testable type for repo_config.t *)
let repo_config_testable =
  let pp fmt config =
    Stdlib.Format.fprintf fmt
      "{ github_owner=%s; github_repo=%s; github_installation_id=%s; \
       gitlab_domain=%s; org_name=%s }"
      config.github_owner config.github_repo
      (Option.value ~default:"None"
         (Option.map config.github_installation_id ~f:Int.to_string) )
      (Option.value ~default:"None" config.gitlab_domain)
      (Option.value ~default:"None" config.org_name)
  in
  let equal a b =
    String.equal a.github_owner b.github_owner
    && String.equal a.github_repo b.github_repo
    && Option.equal Int.equal a.github_installation_id b.github_installation_id
    && Option.equal String.equal a.gitlab_domain b.gitlab_domain
    && Option.equal String.equal a.gitlab_owner b.gitlab_owner
    && Option.equal String.equal a.gitlab_repo b.gitlab_repo
    && Option.equal Int.equal a.github_project_number b.github_project_number
    && Option.equal String.equal a.org_name b.org_name
    && Option.equal String.equal a.team_name b.team_name
    && Option.equal String.equal a.minimizer_url b.minimizer_url
  in
  testable pp equal

let test_minimal_config () =
  let toml_str = {|
[repositories.rocq]
github = "rocq-prover/rocq"
|} in
  let toml_data = Utils.toml_of_string toml_str in
  let configs = parse_all_repo_configs toml_data in
  check
    (list repo_config_testable)
    "should parse one config"
    [ { github_owner= "rocq-prover"
      ; github_repo= "rocq"
      ; gitlab_domain= None
      ; gitlab_owner= None
      ; gitlab_repo= None
      ; github_installation_id= None
      ; github_project_number= None
      ; org_name= None
      ; team_name= None
      ; minimizer_url= None
      ; ci_config= None
      ; labels= None
      ; jobs= None
      ; documentation= None } ]
    configs ;
  check int "should have exactly one config" 1 (List.length configs) ;
  let config = List.hd_exn configs in
  check string "github_owner" config.github_owner "rocq-prover" ;
  check string "github_repo" config.github_repo "rocq" ;
  check (option int) "github_installation_id" config.github_installation_id None

let test_full_config () =
  let toml_str =
    {|
[repositories.rocq]
github = "rocq-prover/rocq"
github_installation_id = "1062161"
github_project_number = "11"
gitlab_domain = "gitlab.inria.fr"
gitlab_owner = "coq"
gitlab_repo = "coq"
org_name = "rocq-prover"
team_name = "contributors"
minimizer_url = "https://github.com/rocq-community/run-coq-bug-minimizer/actions"

[repositories.rocq.ci]
full_ci_variable = "FULL_CI"
skip_docker_variable = "SKIP_DOCKER"
docker_path_pattern = "dev/ci/docker/.*Dockerfile.*"

[repositories.rocq.labels]
needs_rebase = "needs: rebase"
stale = "stale"
needs_full_ci = "needs: full CI"
request_full_ci = "request: full CI"
needs_independent_fix = "needs: independent fix"

[repositories.rocq.jobs]
bench = "bench"
doc_refman = "doc:refman|doc:ci-refman"
doc_init = "doc:init"
doc_stdlib = "doc:stdlib|doc:stdlib:dune"
doc_ml_api = "doc:ml-api:odoc"

[repositories.rocq.documentation]
refman_path = "_build/default/doc/refman-html/index.html"
corelib_path = "_build/default/doc/corelib/html/index.html"
stdlib_path = "_build/default/doc/stdlib/html/index.html"
ml_api_path = "_build/default/_doc/_html/index.html"
|}
  in
  let toml_data = Utils.toml_of_string toml_str in
  let configs = parse_all_repo_configs toml_data in
  check int "should have exactly one config" (List.length configs) 1 ;
  let config = List.hd_exn configs in
  check string "github_owner" config.github_owner "rocq-prover" ;
  check string "github_repo" config.github_repo "rocq" ;
  check (option int) "github_installation_id" config.github_installation_id
    (Some 1062161) ;
  check (option int) "github_project_number" config.github_project_number
    (Some 11) ;
  check (option string) "gitlab_domain" config.gitlab_domain
    (Some "gitlab.inria.fr") ;
  check (option string) "gitlab_owner" config.gitlab_owner (Some "coq") ;
  check (option string) "gitlab_repo" config.gitlab_repo (Some "coq") ;
  check (option string) "org_name" config.org_name (Some "rocq-prover") ;
  check (option string) "team_name" config.team_name (Some "contributors") ;
  check (option string) "minimizer_url" config.minimizer_url
    (Some "https://github.com/rocq-community/run-coq-bug-minimizer/actions") ;
  (* Check CI config *)
  ( match config.ci_config with
  | Some ci ->
      check (option string) "full_ci_variable" ci.full_ci_variable
        (Some "FULL_CI") ;
      check (option string) "skip_docker_variable" ci.skip_docker_variable
        (Some "SKIP_DOCKER") ;
      check (option string) "docker_path_pattern" ci.docker_path_pattern
        (Some "dev/ci/docker/.*Dockerfile.*")
  | None ->
      Alcotest.fail "Expected ci_config to be present" ) ;
  (* Check labels config *)
  ( match config.labels with
  | Some labels ->
      check (option string) "needs_rebase" labels.needs_rebase
        (Some "needs: rebase") ;
      check (option string) "stale" labels.stale (Some "stale") ;
      check (option string) "needs_full_ci" labels.needs_full_ci
        (Some "needs: full CI")
  | None ->
      Alcotest.fail "Expected labels config to be present" ) ;
  (* Check jobs config *)
  ( match config.jobs with
  | Some jobs ->
      check (option string) "bench" jobs.bench (Some "bench") ;
      check
        (option (list string))
        "doc_refman" jobs.doc_refman
        (Some ["doc:refman"; "doc:ci-refman"]) ;
      check (option string) "doc_init" jobs.doc_init (Some "doc:init") ;
      check
        (option (list string))
        "doc_stdlib" jobs.doc_stdlib
        (Some ["doc:stdlib"; "doc:stdlib:dune"]) ;
      check (option string) "doc_ml_api" jobs.doc_ml_api (Some "doc:ml-api:odoc")
  | None ->
      Alcotest.fail "Expected jobs config to be present" ) ;
  (* Check documentation config *)
  match config.documentation with
  | Some doc ->
      check (option string) "refman_path" doc.refman_path
        (Some "_build/default/doc/refman-html/index.html") ;
      check (option string) "corelib_path" doc.corelib_path
        (Some "_build/default/doc/corelib/html/index.html") ;
      check (option string) "stdlib_path" doc.stdlib_path
        (Some "_build/default/doc/stdlib/html/index.html") ;
      check (option string) "ml_api_path" doc.ml_api_path
        (Some "_build/default/_doc/_html/index.html")
  | None ->
      Alcotest.fail "Expected documentation config to be present"

let test_multiple_repositories () =
  let toml_str =
    {|
[repositories.rocq]
github = "rocq-prover/rocq"
gitlab_domain = "gitlab.inria.fr"
gitlab_owner = "coq"
gitlab_repo = "coq"

[repositories.coq]
github = "coq/coq"
gitlab_domain = "gitlab.com"
gitlab_owner = "coq"
gitlab_repo = "coq"

[repositories.mathcomp]
github = "math-comp/math-comp"
gitlab_domain = "gitlab.inria.fr"
gitlab_owner = "math-comp"
gitlab_repo = "math-comp"
|}
  in
  let toml_data = Utils.toml_of_string toml_str in
  let configs = parse_all_repo_configs toml_data in
  check int "should have three configs" (List.length configs) 3 ;
  let rocq_config =
    List.find_exn configs ~f:(fun c -> String.equal c.github_repo "rocq")
  in
  let coq_config =
    List.find_exn configs ~f:(fun c -> String.equal c.github_repo "coq")
  in
  let mathcomp_config =
    List.find_exn configs ~f:(fun c -> String.equal c.github_repo "math-comp")
  in
  check string "rocq owner" rocq_config.github_owner "rocq-prover" ;
  check (option string) "rocq gitlab_domain" rocq_config.gitlab_domain
    (Some "gitlab.inria.fr") ;
  check (option string) "rocq gitlab_owner" rocq_config.gitlab_owner (Some "coq") ;
  check (option string) "rocq gitlab_repo" rocq_config.gitlab_repo (Some "coq") ;
  check string "coq owner" coq_config.github_owner "coq" ;
  check (option string) "coq gitlab_domain" coq_config.gitlab_domain
    (Some "gitlab.com") ;
  (* coq/coq doesn't have hardcoded installation_id in the codebase *)
  check (option int) "coq installation_id" coq_config.github_installation_id
    None ;
  check string "mathcomp owner" mathcomp_config.github_owner "math-comp" ;
  check (option string) "mathcomp gitlab_domain" mathcomp_config.gitlab_domain
    (Some "gitlab.inria.fr") ;
  check (option string) "mathcomp gitlab_owner" mathcomp_config.gitlab_owner
    (Some "math-comp") ;
  check (option string) "mathcomp gitlab_repo" mathcomp_config.gitlab_repo
    (Some "math-comp")

let test_config_table () =
  let toml_str =
    {|
[repositories.rocq]
github = "rocq-prover/rocq"

[repositories.coq]
github = "coq/coq"
|}
  in
  let toml_data = Utils.toml_of_string toml_str in
  let table = create_repo_config_table toml_data in
  check bool "has rocq config"
    (has_repo_config ~owner:"rocq-prover" ~repo:"rocq" table)
    true ;
  check bool "has coq config"
    (has_repo_config ~owner:"coq" ~repo:"coq" table)
    true ;
  check bool "doesn't have unknown config"
    (has_repo_config ~owner:"unknown" ~repo:"repo" table)
    false ;
  let rocq_config = get_repo_config ~owner:"rocq-prover" ~repo:"rocq" table in
  check string "table lookup rocq" rocq_config.github_repo "rocq" ;
  let coq_config = get_repo_config ~owner:"coq" ~repo:"coq" table in
  check string "table lookup coq" coq_config.github_repo "coq"

let test_pipe_separated_jobs () =
  let toml_str =
    {|
[repositories.test]
github = "test/test"

[repositories.test.jobs]
doc_refman = "job1|job2|job3"
doc_stdlib = "single-job"
|}
  in
  let toml_data = Utils.toml_of_string toml_str in
  let configs = parse_all_repo_configs toml_data in
  let config = List.hd_exn configs in
  match config.jobs with
  | Some jobs ->
      check
        (option (list string))
        "pipe separated doc_refman" jobs.doc_refman
        (Some ["job1"; "job2"; "job3"]) ;
      check
        (option (list string))
        "single doc_stdlib" jobs.doc_stdlib (Some ["single-job"])
  | None ->
      Alcotest.fail "Expected jobs config to be present"

let () =
  run "Repo_config"
    [ ( "parsing"
      , [ test_case "minimal configuration" `Quick test_minimal_config
        ; test_case "full configuration" `Quick test_full_config
        ; test_case "multiple repositories" `Quick test_multiple_repositories
        ; test_case "pipe separated jobs" `Quick test_pipe_separated_jobs ] )
    ; ("lookup", [test_case "config table" `Quick test_config_table]) ]
