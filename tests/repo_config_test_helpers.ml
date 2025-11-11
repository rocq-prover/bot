open Base
open Repo_config
open Alcotest

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
