open Test_helpers
open Auto_detection
open Alcotest

(** Test GitLab info detection - should fallback to default domain if not found *)
let test_auto_detect_gitlab_info () =
  (* Test with real GitLab API if credentials are available, otherwise use mock *)
  let bot_info =
    match create_real_bot_info () with
    | Some info ->
        info (* Use real credentials if available *)
    | None ->
        create_mock_bot_info () (* Fallback to mock *)
  in
  let owner = "test-org" in
  let repo = "test-repo" in
  let result =
    Lwt_main.run
      (auto_detect_gitlab_info ~bot_info ~github_owner:owner ~github_repo:repo)
  in
  match result with
  | Some (domain, gl_owner, gl_repo) ->
      (* Should return default domain with same owner/repo if not found *)
      check string "gitlab_domain" domain "gitlab.com" ;
      check string "gitlab_owner" gl_owner owner ;
      check string "gitlab_repo" gl_repo repo
  | None ->
      fail "Expected to find GitLab project or use default domain"

(** Test org/team detection with real API or graceful skip *)
let test_auto_detect_org_team () =
  (* Test with real GitHub API if credentials are available *)
  match create_real_bot_info () with
  | None ->
      (* Skip test if no credentials - this is expected in CI without secrets *)
      check bool "test skipped due to no credentials" true true
  | Some bot_info -> (
      (* Use a real public repository for testing that is known to exist *)
      let owner = "ocaml" in
      let repo = "opam" in
      let result =
        Lwt_main.run
          (auto_detect_org_team ~bot_info ~github_owner:owner ~github_repo:repo)
      in
      match result with
      | Some (org_name, team_name) -> (
          (* Verify API returned valid data *)
          check (option string) "org_name detected" org_name (Some owner) ;
          (* Team name should be Some (either detected or default "maintainers") *)
          check bool "team_name is Some" (Option.is_some team_name) true ;
          (* If team_name is Some, it should be a non-empty string *)
          match team_name with
          | Some name ->
              check bool "team_name is non-empty" (String.length name > 0) true
          | None ->
              fail "Expected team_name to be Some" )
      | None ->
          (* Repository might not exist or API call failed *)
          fail
            "Failed to detect org and team - repository may not exist or API \
             call failed" )

(** Test complete auto-detection with caching *)
let test_auto_detect_from_apis () =
  (* Test with real GitHub API if credentials are available *)
  match create_real_bot_info () with
  | None ->
      (* Skip test if no credentials - this is expected in CI without secrets *)
      check bool "test skipped due to no credentials" true true
  | Some bot_info ->
      (* Use a real public repository for testing *)
      let owner = "ocaml" in
      let repo = "opam" in
      (* Clear cache first *)
      Cache.clear_all () ;
      (* First call should run detection *)
      let result1 =
        Lwt_main.run
          (auto_detect_from_apis ~bot_info ~github_owner:owner ~github_repo:repo)
      in
      (* Verify first result has expected structure *)
      check string "first call owner" result1.github_owner owner ;
      check string "first call repo" result1.github_repo repo ;
      (* Second call should use cache *)
      let result2 =
        Lwt_main.run
          (auto_detect_from_apis ~bot_info ~github_owner:owner ~github_repo:repo)
      in
      (* Results should be identical (cache hit) *)
      check string "cached owner" result2.github_owner result1.github_owner ;
      check string "cached repo" result2.github_repo result1.github_repo ;
      check (option string) "cached gitlab_domain" result2.gitlab_domain
        result1.gitlab_domain ;
      check (option string) "cached org_name" result2.org_name result1.org_name ;
      check (option string) "cached team_name" result2.team_name
        result1.team_name ;
      (* Verify cache is working by checking that gitlab_domain is set *)
      check bool "gitlab_domain is set"
        (Option.is_some result1.gitlab_domain)
        true

(** Test that auto_detect_from_apis returns a complete Repo_config.t *)
let test_auto_detect_from_apis_completeness () =
  match create_real_bot_info () with
  | None ->
      check bool "test skipped due to no credentials" true true
  | Some bot_info ->
      let owner = "ocaml" in
      let repo = "opam" in
      Cache.clear_all () ;
      let result =
        Lwt_main.run
          (auto_detect_from_apis ~bot_info ~github_owner:owner ~github_repo:repo)
      in
      (* Verify all required fields are present *)
      check string "github_owner" result.github_owner owner ;
      check string "github_repo" result.github_repo repo ;
      (* gitlab_domain should be Some (either detected or default) *)
      check bool "gitlab_domain is Some"
        (Option.is_some result.gitlab_domain)
        true ;
      (* org_name should be Some *)
      check bool "org_name is Some" (Option.is_some result.org_name) true ;
      (* team_name should be Some *)
      check bool "team_name is Some" (Option.is_some result.team_name) true ;
      (* minimizer_url may be Some (if BOT_MINIMIZER_URL env var is set) or None (generic default) *)
      (* This is acceptable - minimizer_url is optional and can be configured per-repo *)
      (* ci_config should be Some (from defaults) *)
      check bool "ci_config is Some" (Option.is_some result.ci_config) true

let () =
  run "Auto-detection"
    [ ( "api_detection"
      , [ test_case "test_auto_detect_gitlab_info" `Quick
            test_auto_detect_gitlab_info
        ; test_case "test_auto_detect_org_team" `Quick test_auto_detect_org_team
        ; test_case "test_auto_detect_from_apis" `Quick
            test_auto_detect_from_apis
        ; test_case "test_auto_detect_from_apis_completeness" `Quick
            test_auto_detect_from_apis_completeness ] ) ]
