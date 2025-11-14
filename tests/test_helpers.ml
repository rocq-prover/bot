open Base
open Bot_components
open Repo_config
open Alcotest

(** Create a mock bot_info for testing *)
let create_mock_bot_info () =
  let gitlab_instances = Hashtbl.create (module String) in
  Hashtbl.set gitlab_instances ~key:"gitlab.com"
    ~data:("test-name", "test-token") ;
  { Bot_info.github_install_token= None
  ; gitlab_instances
  ; github_name= "test-bot"
  ; email= "test-bot@users.noreply.github.com"
  ; domain= "test-bot.herokuapp.com"
  ; app_id= 12345
  ; api_timeout= 5.0 }

(** Create a real bot_info from environment variables for integration testing.
    Returns None if GITHUB_ACCESS_TOKEN is not set. *)
let create_real_bot_info () =
  match Sys.getenv "GITHUB_ACCESS_TOKEN" with
  | None ->
      None
  | Some token ->
      let gitlab_instances = Hashtbl.create (module String) in
      (* Add gitlab.com if GITLAB_ACCESS_TOKEN is available *)
      ( match Sys.getenv "GITLAB_ACCESS_TOKEN" with
      | Some gitlab_token ->
          Hashtbl.set gitlab_instances ~key:"gitlab.com"
            ~data:("test-bot", gitlab_token)
      | None ->
          () ) ;
      Some
        { Bot_info.github_install_token= Some token
        ; gitlab_instances
        ; github_name= "test-bot"
        ; email= "test-bot@users.noreply.github.com"
        ; domain= "test-bot.herokuapp.com"
        ; app_id= 12345
        ; api_timeout= 5.0 }

(** Alcotest testable for Repo_config.t *)
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

(** Helper to check that a function raises a Failure exception *)
let check_raises_failure msg f =
  try
    f () ;
    Alcotest.fail (msg ^ ": expected Failure exception, but none was raised")
  with
  | Failure _ ->
      () (* Expected *)
  | e ->
      Alcotest.fail
        (msg ^ ": expected Failure exception, but got: " ^ Exn.to_string e)

(** Get bot_info for testing: tries real credentials first, falls back to mock *)
let get_bot_info () =
  match create_real_bot_info () with
  | Some info ->
      info
  | None ->
      create_mock_bot_info ()

(** Helper to create a test Repo_config.t for testing *)
let create_test_config ~owner ~repo ~gitlab_domain =
  { github_owner= owner
  ; github_repo= repo
  ; gitlab_domain= Some gitlab_domain
  ; gitlab_owner= Some owner
  ; gitlab_repo= Some repo
  ; github_installation_id= None
  ; github_project_number= None
  ; org_name= Some owner
  ; team_name= Some "maintainers"
  ; minimizer_url= None
  ; ci_config= None
  ; labels= None
  ; jobs= None
  ; documentation= None }
