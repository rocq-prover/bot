open Base
open Alcotest

let parse s = Repo_config.make_repo_config_table (Utils.toml_of_string s)

let test_full_config () =
  let toml =
    {|
    [repositories.rocq]
    github = "rocq-prover/rocq"
    gitlab_domain = "gitlab.inria.fr"
    gitlab_owner = "coq"
    gitlab_repo = "coq"
    github_installation_id = 1062161
    org_name = "rocq-prover"
    alert_mention = "@rocq-prover/coqbot-maintainers"
    minimizer_url = "https://example.com"

    [repositories.rocq.backporting]
    github_project_number = 11

    [[repositories.rocq.teams]]
    team_name = "contributors"
    permission = "contribute"

    [[repositories.rocq.teams]]
    team_name = "pushers"
    permission = "push"

    [repositories.rocq.jobs]
    bench_job = "bench"
    use_rocq_job_status = true
    silence_docker_manifest_errors = true
    doc_artifact_jobs = ["doc:refman", "doc:stdlib"]
    |}
  in
  let tbl = parse toml in
  match Repo_config.find_by_github ~owner:"rocq-prover" ~repo:"rocq" tbl with
  | None ->
      fail "expected config"
  | Some cfg ->
      (check (option int))
        "project" (Some 11) cfg.backporting.github_project_number ;
      (check (option string))
        "alert" (Some "@rocq-prover/coqbot-maintainers") cfg.alert_mention ;
      (check int) "teams" 2 (List.length cfg.teams) ;
      (check (option string)) "bench_job" (Some "bench") cfg.jobs.bench_job ;
      (check bool) "use_rocq_job_status" true cfg.jobs.use_rocq_job_status ;
      (check bool) "silence_docker_manifest_errors" true
        cfg.jobs.silence_docker_manifest_errors ;
      (check int) "doc_artifact_jobs" 2 (List.length cfg.jobs.doc_artifact_jobs)

let test_minimal_config () =
  let tbl = parse {|
  [repositories.demo]
  github = "my-org/my-repo"
  |} in
  match Repo_config.find_by_github ~owner:"my-org" ~repo:"my-repo" tbl with
  | None ->
      fail "expected config"
  | Some cfg ->
      (check (option int)) "project" None cfg.backporting.github_project_number ;
      (check bool) "use_rocq_job_status" false cfg.jobs.use_rocq_job_status ;
      (check (list string)) "doc_artifact_jobs" [] cfg.jobs.doc_artifact_jobs

let test_bad_github () =
  check_raises "bad github"
    (Failure "repositories.demo: 'github' must be 'owner/repo', got 'bad'")
    (fun () -> ignore (parse {|
  [repositories.demo]
  github = "bad"
  |} ) )

let test_missing_section () =
  let tbl = parse "" in
  (check int) "empty" 0 (Hashtbl.length tbl)

let test_find_miss () =
  let tbl = parse {|
  [repositories.demo]
  github = "my-org/my-repo"
|} in
  (check bool) "miss" true
    (Option.is_none
       (Repo_config.find_by_github ~owner:"other" ~repo:"repo" tbl) )

let test_backport_enabled () =
  let with_project =
    parse
      {|
    [repositories.rocq]
    github = "rocq-prover/rocq"
    github_installation_id = 102161
    org_name = "rocq-prover"

    [repositories.rocq.backporting]
    github_project_number = 11
    |}
  in
  let without_project =
    parse {|
    [repositories.demo]
    github = "my-org/my-repo"
    |}
  in
  let cfg_on =
    Option.value_exn
      (Repo_config.find_by_github ~owner:"rocq-prover" ~repo:"rocq" with_project)
  in
  let cfg_off =
    Option.value_exn
      (Repo_config.find_by_github ~owner:"my-org" ~repo:"my-repo"
         without_project )
  in
  (check bool) "enabled" true (Repo_config.backport_enabled cfg_on) ;
  (check bool) "disabled" false (Repo_config.backport_enabled cfg_off) ;
  (check string) "org" "rocq-prover" (Repo_config.project_organization cfg_on) ;
  (check string) "org fallback" "my-org"
    (Repo_config.project_organization cfg_off) ;
  (check bool) "card match" true
    (Option.is_some
       (Repo_config.find_by_backport_project ~install_id:102161
          ~project_number:11 with_project ) ) ;
  (check bool) "card miss" true
    (Option.is_none
       (Repo_config.find_by_backport_project ~install_id:102161
          ~project_number:11 without_project ) )

let test_jobs_helper () =
  let with_jobs =
    parse
      {|
    [repositories.rocq]
    github = "rocq-prover/rocq"
    gitlab_domain = "gitlab.inria.fr"
    gitlab_owner = "coq"
    gitlab_repo = "coq"

    [repositories.rocq.jobs]
    bench_job = "bench"
    use_rocq_job_status = true
    silence_docker_manifest_errors = true
    doc_artifact_jobs = ["doc:refman", "doc:stdlib"]
    |}
  in
  let without_jobs =
    parse {|
  [repositories.demo]
  github = "my-org/my-repo"
  |}
  in
  let cfg_on =
    Option.value_exn
      (Repo_config.find_by_github ~owner:"rocq-prover" ~repo:"rocq" with_jobs)
  in
  let cfg_off =
    Option.value_exn
      (Repo_config.find_by_github ~owner:"my-org" ~repo:"my-repo" without_jobs)
  in
  (check bool) "bench on" true (Repo_config.is_bench_job cfg_on "bench") ;
  (check bool) "bench wrong name" false
    (Repo_config.is_bench_job cfg_on "build") ;
  (check bool) "bench absent" false
    (Repo_config.is_bench_job cfg_off "bench_job") ;
  (check bool) "doc on" true
    (Repo_config.is_doc_artifact_job cfg_on "doc:refman") ;
  (check bool) "doc off" false
    (Repo_config.is_doc_artifact_job cfg_off "doc:refman") ;
  (check string) "gh name" "rocq-prover/rocq"
    (Repo_config.github_full_name cfg_on) ;
  (check (option string))
    "job url" (Some "https://gitlab.inria.fr/coq/coq/-/jobs/42")
    (Repo_config.gitlab_job_url cfg_on ~job_id:42) ;
  (check (option string))
    "pages url"
    (Some
       "https://coq.gitlabpages.inria.fr/-/coq/-/jobs/42/artifacts/doc/index.html"
    )
    (Repo_config.gitlab_pages_artifact_url cfg_on ~job_id:42
       ~artifact:"doc/index.html" ) ;
  (check (option string))
    "job url missing" None
    (Repo_config.gitlab_job_url cfg_off ~job_id:1)

let () =
  run "Repo_config tests"
    [ ( "parse"
      , [ ("full config", `Quick, test_full_config)
        ; ("minimal config", `Quick, test_minimal_config)
        ; ("bad github", `Quick, test_bad_github)
        ; ("missing section", `Quick, test_missing_section)
        ; ("find miss", `Quick, test_find_miss)
        ; ("backport enabled", `Quick, test_backport_enabled)
        ; ("jobs", `Quick, test_jobs_helper) ] ) ]
