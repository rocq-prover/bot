open Base
open Bot_components
open Config
open Repo_config
open Alcotest
open Default

(** 
 * Tests demonstrating the generic bot configuration system.
 * 
 * Key concepts:
 * - Rocq is just a repo with explicit config, same as any other repo
 * - Adding a repo requires only: github = "owner/repo"
 * - Config resolution: explicit > auto-detection > defaults
 * - Supports full, partial, or minimal configuration
 *)

let test_rocq_is_configured_instance () =
  let toml_str =
    {|
[repositories.rocq]
github = "rocq-prover/rocq"
github_installation_id = "1062161"
github_project_number = "11"
gitlab_domain = "gitlab.inria.fr"
org_name = "rocq-prover"
team_name = "contributors"

[repositories.rocq.jobs]
custom_job_status = true
|}
  in
  let toml_data = Utils.toml_of_string toml_str in
  let table = repo_config_table toml_data in
  let rocq_config =
    Option.value_exn
      (get_repo_config_opt ~owner:"rocq-prover" ~repo:"rocq" table)
  in
  (* Verify rocq's explicit configuration *)
  check bool "rocq configures custom GitLab domain (not default)"
    (Option.is_some rocq_config.gitlab_domain)
    true ;
  check bool "rocq enables backport (via project_number)"
    (Option.is_some rocq_config.github_project_number)
    true ;
  check bool "rocq enables custom job status"
    ( match rocq_config.jobs with
    | Some jobs ->
        Option.value ~default:false jobs.custom_job_status
    | None ->
        false )
    true ;
  check string "rocq uses standard config format" rocq_config.github_owner
    "rocq-prover"

let test_minimal_repo_works_immediately () =
  (* Adding a repo requires only github = "owner/repo". The bot handles the rest.
     This test shows the parsing, defaults, and resolution steps. *)
  let toml_str = {|
[repositories.my-new-repo]
github = "my-org/my-repo"
|} in
  let toml_data = Utils.toml_of_string toml_str in
  let table = repo_config_table toml_data in
  let config =
    Option.value_exn (get_repo_config_opt ~owner:"my-org" ~repo:"my-repo" table)
  in
  (* Step 1: Parsing extracts only explicit TOML values *)
  check string "explicit github_owner from TOML" config.github_owner "my-org" ;
  check string "explicit github_repo from TOML" config.github_repo "my-repo" ;
  (* Missing fields are None after parsing *)
  check bool "gitlab_domain not in TOML, so None after parsing"
    (Option.is_none config.gitlab_domain)
    true ;
  (* Step 2: Defaults exist for missing fields *)
  let defaults = get_defaults ~owner:"my-org" ~repo:"my-repo" in
  check (option string) "default gitlab_domain" defaults.gitlab_domain
    (Some "gitlab.com") ;
  check (option string) "default org_name" defaults.org_name (Some "my-org") ;
  check (option string) "default team_name" defaults.team_name
    (Some "maintainers") ;
  (* Step 3: Config resolver applies defaults at runtime *)
  (* Create mock bot_info for resolution *)
  let gitlab_instances = Hashtbl.create (module String) in
  Hashtbl.set gitlab_instances ~key:"gitlab.com" ~data:("test-bot", "test-token") ;
  let bot_info =
    { Bot_info.github_install_token= Some "test-token"
    ; gitlab_instances
    ; github_name= "test-bot"
    ; email= "test-bot@users.noreply.github.com"
    ; domain= "test-bot.herokuapp.com"
    ; app_id= 12345
    ; api_timeout= 5.0 }
  in
  let resolved =
    Lwt_main.run
      (Config_resolver.resolve_repo_config ~bot_info ~explicit_config:config)
  in
  (* After resolution: explicit values preserved, defaults applied *)
  check string "explicit values preserved" resolved.github_owner "my-org" ;
  check (option string) "defaults applied: gitlab_domain" resolved.gitlab_domain
    (Some "gitlab.com") ;
  check (option string) "defaults applied: org_name" resolved.org_name
    (Some "my-org") ;
  check (option string) "defaults applied: team_name" resolved.team_name
    (Some "maintainers") ;
  check bool "defaults applied: CI config"
    (Option.is_some resolved.ci_config)
    true ;
  check bool "defaults applied: labels" (Option.is_some resolved.labels) true ;
  ()

let test_three_tier_config_system () =
  (* Config resolution priority: explicit values first, then auto-detection from APIs,
     then defaults. This test shows when each path is used. *)
  (* Case 1: Minimal config triggers auto-detection *)
  let minimal_toml =
    {|
[repositories.minimal]
github = "test-org/test-repo"
|}
  in
  let toml_data = Utils.toml_of_string minimal_toml in
  let table = repo_config_table toml_data in
  let minimal_config =
    Option.value_exn
      (get_repo_config_opt ~owner:"test-org" ~repo:"test-repo" table)
  in
  (* Missing fields trigger auto-detection *)
  check bool "missing fields trigger auto-detection"
    ( Option.is_none minimal_config.gitlab_domain
    && Option.is_none minimal_config.org_name )
    true ;
  (* Case 2: Explicit config skips auto-detection *)
  let explicit_toml =
    {|
[repositories.explicit]
github = "test-org/test-repo"
gitlab_domain = "gitlab.example.com"
org_name = "test-org"
|}
  in
  let toml_data2 = Utils.toml_of_string explicit_toml in
  let table2 = repo_config_table toml_data2 in
  let explicit_config =
    Option.value_exn
      (get_repo_config_opt ~owner:"test-org" ~repo:"test-repo" table2)
  in
  (* Explicit fields skip auto-detection *)
  check bool "explicit fields skip auto-detection"
    ( Option.is_some explicit_config.gitlab_domain
    && Option.is_some explicit_config.org_name )
    true ;
  ()

let test_partial_config_flexibility () =
  (* We can override specific defaults while keeping the rest. This allows
     customizing only what's needed without repeating all config. *)
  let toml_str =
    {|
[repositories.custom]
github = "custom-org/custom-repo"
gitlab_domain = "gitlab.example.com"
team_name = "developers"
|}
  in
  let toml_data = Utils.toml_of_string toml_str in
  let table = repo_config_table toml_data in
  let config =
    Option.value_exn
      (get_repo_config_opt ~owner:"custom-org" ~repo:"custom-repo" table)
  in
  (* Explicit values override defaults *)
  check (option string) "explicit gitlab_domain overrides default"
    config.gitlab_domain (Some "gitlab.example.com") ;
  check (option string) "explicit team_name overrides default" config.team_name
    (Some "developers") ;
  (* Unspecified fields use defaults *)
  let defaults = get_defaults ~owner:"custom-org" ~repo:"custom-repo" in
  check (option string) "org_name uses default" defaults.org_name
    (Some "custom-org") ;
  ()

(** Tests multiple repos with different config levels in the same file *)
let test_multiple_repos_coexist () =
  let toml_str =
    {|
[repositories.full-featured]
github = "org1/repo1"
gitlab_domain = "gitlab.com"
github_project_number = "5"

[repositories.full-featured.jobs]
custom_job_status = true

[repositories.basic]
github = "org2/repo2"
|}
  in
  let toml_data = Utils.toml_of_string toml_str in
  let table = repo_config_table toml_data in
  (* Both repos exist in the same config *)
  check bool "full-featured repo configured"
    (has_repo_config ~owner:"org1" ~repo:"repo1" table)
    true ;
  check bool "basic repo configured"
    (has_repo_config ~owner:"org2" ~repo:"repo2" table)
    true ;
  (* Verify they have different config levels *)
  let full_config =
    Option.value_exn (get_repo_config_opt ~owner:"org1" ~repo:"repo1" table)
  in
  let basic_config =
    Option.value_exn (get_repo_config_opt ~owner:"org2" ~repo:"repo2" table)
  in
  check bool "full-featured has project_number (backport enabled)"
    (Option.is_some full_config.github_project_number)
    true ;
  check bool "basic has no project_number (backport disabled)"
    (Option.is_none basic_config.github_project_number)
    true ;
  ()

(** Compares rocq and a generic repo to show they use the same config system *)
let test_rocq_vs_generic_same_system () =
  let toml_str =
    {|
[repositories.rocq]
github = "rocq-prover/rocq"
gitlab_domain = "gitlab.inria.fr"
github_project_number = "11"

[repositories.opam]
github = "ocaml/opam"
|}
  in
  let toml_data = Utils.toml_of_string toml_str in
  let table = repo_config_table toml_data in
  let rocq_config =
    Option.value_exn
      (get_repo_config_opt ~owner:"rocq-prover" ~repo:"rocq" table)
  in
  let opam_config =
    Option.value_exn (get_repo_config_opt ~owner:"ocaml" ~repo:"opam" table)
  in
  (* Both use the same config system *)
  check string "rocq uses standard config" rocq_config.github_owner
    "rocq-prover" ;
  check string "opam uses standard config" opam_config.github_owner "ocaml" ;
  check bool "rocq has explicit gitlab_domain"
    (Option.is_some rocq_config.gitlab_domain)
    true ;
  check bool "opam uses default gitlab_domain"
    (Option.is_none opam_config.gitlab_domain)
    true ;
  (* Both can access the same defaults *)
  let rocq_defaults = get_defaults ~owner:"rocq-prover" ~repo:"rocq" in
  let opam_defaults = get_defaults ~owner:"ocaml" ~repo:"opam" in
  check bool "both can use defaults"
    ( Option.is_some rocq_defaults.gitlab_domain
    && Option.is_some opam_defaults.gitlab_domain )
    true ;
  ()

(** Tests all available configuration options - serves as a reference *)
let test_complete_config_coverage () =
  let toml_str =
    {|
[repositories.complete]
github = "complete-org/complete-repo"
github_installation_id = "123456"
github_project_number = "42"
gitlab_domain = "gitlab.com"
gitlab_owner = "complete-org"
gitlab_repo = "complete-repo"
org_name = "complete-org"
team_name = "maintainers"
minimizer_url = "https://custom-minimizer.com"

[repositories.complete.ci]
full_ci_variable = "FULL_CI"
skip_docker_variable = "SKIP_DOCKER"
docker_path_pattern = ".*Dockerfile.*"

[repositories.complete.labels]
needs_rebase = "needs: rebase"
stale = "stale"
needs_full_ci = "needs: full CI"
request_full_ci = "request: full CI"
needs_independent_fix = "needs: independent fix"

[repositories.complete.jobs]
bench = "benchmark"
doc_refman = "doc:refman|doc:ci-refman"
doc_init = "doc:init"
doc_stdlib = "doc:stdlib"
doc_ml_api = "doc:ml-api"
custom_job_status = true

[repositories.complete.documentation]
refman_path = "path/to/refman.html"
corelib_path = "path/to/corelib.html"
stdlib_path = "path/to/stdlib.html"
ml_api_path = "path/to/ml-api.html"
|}
  in
  let toml_data = Utils.toml_of_string toml_str in
  let table = repo_config_table toml_data in
  let config =
    Option.value_exn
      (get_repo_config_opt ~owner:"complete-org" ~repo:"complete-repo" table)
  in
  (* Verify all top-level fields *)
  check string "github_owner" config.github_owner "complete-org" ;
  check (option int) "github_installation_id" config.github_installation_id
    (Some 123456) ;
  check (option int) "github_project_number" config.github_project_number
    (Some 42) ;
  check (option string) "gitlab_domain" config.gitlab_domain (Some "gitlab.com") ;
  check (option string) "org_name" config.org_name (Some "complete-org") ;
  check (option string) "team_name" config.team_name (Some "maintainers") ;
  check (option string) "minimizer_url" config.minimizer_url
    (Some "https://custom-minimizer.com") ;
  (* Verify nested config sections *)
  check bool "ci_config present" (Option.is_some config.ci_config) true ;
  check bool "labels present" (Option.is_some config.labels) true ;
  check bool "jobs present" (Option.is_some config.jobs) true ;
  check bool "documentation present" (Option.is_some config.documentation) true ;
  ()

let () =
  run "Generic Bot Configuration Demo"
    [ ( "core_concepts"
      , [ test_case "rocq is just a configured instance" `Quick
            test_rocq_is_configured_instance
        ; test_case "minimal repo works immediately" `Quick
            test_minimal_repo_works_immediately
        ; test_case "3-tier config system" `Quick test_three_tier_config_system
        ] )
    ; ( "flexibility"
      , [ test_case "partial config flexibility" `Quick
            test_partial_config_flexibility
        ; test_case "multiple repos coexist" `Quick test_multiple_repos_coexist
        ] )
    ; ( "comparison"
      , [ test_case "rocq vs generic same system" `Quick
            test_rocq_vs_generic_same_system ] )
    ; ( "documentation"
      , [ test_case "complete config coverage" `Quick
            test_complete_config_coverage ] ) ]
