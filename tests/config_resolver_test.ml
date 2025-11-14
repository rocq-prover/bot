open Repo_config
open Alcotest
open Test_helpers

let bot_info = get_bot_info ()

let test_merge_priority_explicit_overrides () =
  let explicit_config =
    { github_owner= "explicit-org"
    ; github_repo= "explicit-repo"
    ; gitlab_domain= Some "gitlab.inria.fr"
    ; gitlab_owner= Some "coq"
    ; gitlab_repo= Some "coq"
    ; github_installation_id= Some 12345
    ; github_project_number= Some 11
    ; org_name= Some "explicit-org"
    ; team_name= Some "contributors"
    ; minimizer_url= Some "https://custom-minimizer.com"
    ; ci_config= None
    ; labels= None
    ; jobs= None
    ; documentation= None }
  in
  let result =
    Lwt_main.run
      (Config_resolver.resolve_repo_config ~bot_info ~explicit_config)
  in
  check string "explicit owner" result.github_owner "explicit-org" ;
  check (option string) "explicit gitlab_domain" result.gitlab_domain
    (Some "gitlab.inria.fr") ;
  check (option int) "explicit installation_id" result.github_installation_id
    (Some 12345)

let test_merge_priority_api_fills_gaps () =
  (* Skip test if no real credentials - API calls require installation token *)
  ( match bot_info.github_install_token with
  | None ->
      Alcotest.skip ()
  | Some _ ->
      () ) ;
  let explicit_config =
    { github_owner= "test-org"
    ; github_repo= "test-repo"
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
    ; documentation= None }
  in
  let result =
    Lwt_main.run
      (Config_resolver.resolve_repo_config ~bot_info ~explicit_config)
  in
  (* API should fill in missing values *)
  check (option string) "api gitlab_domain" result.gitlab_domain
    (Some "gitlab.com") ;
  check (option string) "api org_name" result.org_name (Some "test-org") ;
  check (option string) "api team_name" result.team_name (Some "maintainers")

let test_merge_priority_defaults_fallback () =
  ( match bot_info.github_install_token with
  | None ->
      Alcotest.skip ()
  | Some _ ->
      () ) ;
  let explicit_config =
    { github_owner= "unknown-org"
    ; github_repo= "unknown-repo"
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
    ; documentation= None }
  in
  let result =
    Lwt_main.run
      (Config_resolver.resolve_repo_config ~bot_info ~explicit_config)
  in
  (* Defaults should be used when API fails *)
  check (option string) "default gitlab_domain" result.gitlab_domain
    (Some "gitlab.com") ;
  check (option string) "default org_name" result.org_name (Some "unknown-org") ;
  check (option string) "default team_name" result.team_name (Some "maintainers") ;
  match result.ci_config with
  | Some ci ->
      check (option string) "default full_ci_variable" ci.full_ci_variable
        (Some "FULL_CI")
  | None ->
      fail "Expected CI config defaults"

let () =
  run "Config resolver"
    [ ( "merge priority"
      , [ test_case "explicit overrides all" `Quick
            test_merge_priority_explicit_overrides
        ; test_case "api fills gaps" `Quick test_merge_priority_api_fills_gaps
        ; test_case "defaults fallback" `Quick
            test_merge_priority_defaults_fallback ] ) ]
