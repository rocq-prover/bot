open Repo_config
open Bot_components.Utils

(** Shared test helpers for refactored code tests *)

let create_rocq_config () =
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
  let toml_data = toml_of_string toml_str in
  create_repo_config_table toml_data

let create_generic_config ~owner ~repo ?gitlab_domain ?gitlab_owner ?gitlab_repo
    ?org_name ?team_name ?project_number ?bench_job () =
  let gitlab_domain_str =
    match gitlab_domain with
    | Some d ->
        f "gitlab_domain = \"%s\"\n" d
    | None ->
        ""
  in
  let gitlab_owner_str =
    match gitlab_owner with
    | Some o ->
        f "gitlab_owner = \"%s\"\n" o
    | None ->
        ""
  in
  let gitlab_repo_str =
    match gitlab_repo with Some r -> f "gitlab_repo = \"%s\"\n" r | None -> ""
  in
  let org_name_str =
    match org_name with Some o -> f "org_name = \"%s\"\n" o | None -> ""
  in
  let team_name_str =
    match team_name with Some t -> f "team_name = \"%s\"\n" t | None -> ""
  in
  let project_number_str =
    match project_number with
    | Some p ->
        f "github_project_number = \"%d\"\n" p
    | None ->
        ""
  in
  let bench_job_str =
    match bench_job with
    | Some b ->
        f "[repositories.test.jobs]\nbench = \"%s\"\n" b
    | None ->
        ""
  in
  let toml_str =
    f {|
[repositories.test]
github = "%s/%s"
%s%s%s%s%s%s%s
|} owner repo
      gitlab_domain_str gitlab_owner_str gitlab_repo_str org_name_str
      team_name_str project_number_str bench_job_str
  in
  let toml_data = toml_of_string toml_str in
  create_repo_config_table toml_data
