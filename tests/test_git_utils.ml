open Base
open Alcotest

let test_parse_gitlab_repo_url () =
  let check url domain full_name =
    match Git_utils.parse_gitlab_repo_url ~http_repo_url:url with
    | Ok (d, n) ->
        (check string) "domain" domain d ;
        (check string) "full_name" full_name n
    | Error e ->
        fail e
  in
  check "https://gitlab.com/coq/coq" "gitlab.com" "coq/coq" ;
  check "https://gitlab.inria.fr/math-comp/math-comp" "gitlab.inria.fr"
    "math-comp/math-comp" ;
  check "https://gitlab.example.com/gitlab-org/gitlab-test" "gitlab.example.com"
    "gitlab-org/gitlab-test"

let () =
  run "Git_utils tests"
    [ ( "parse_gitlab_repo_url"
      , [test_case "http urls" `Quick test_parse_gitlab_repo_url] ) ]
