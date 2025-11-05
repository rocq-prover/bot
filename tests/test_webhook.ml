open Base
open Bot_components
open Cohttp

(* Webhook payload WITH installation.id (GitHub App mode)
   The only difference from legacy webhooks is the presence of "installation" field *)
let payload =
  {|{
      "action": "opened",
      "installation": {
        "id": 12345
      },
      "repository": {
        "name": "test-repo",
        "owner": {
          "login": "test-owner"
        },
        "html_url": "https://github.com/test-owner/test-repo"
      },
      "pull_request": {
        "number": 1,
        "node_id": "PR_test123",
        "title": "Test PR",
        "html_url": "https://github.com/test-owner/test-repo/pull/1",
        "user": {
          "login": "test-user"
        },
        "labels": [],
        "body": null,
        "assignees": [],
        "base": {
          "ref": "main",
          "sha": "base123",
          "repo": {
            "html_url": "https://github.com/test-owner/test-repo"
          }
        },
        "head": {
          "ref": "feature-branch",
          "sha": "abc123",
          "repo": {
            "html_url": "https://github.com/test-owner/test-repo"
          }
        },
        "merged_at": null
      }
    }|}

(* Test webhook with installation.id *)
let test_webhook_with_installation_id () =
  let install_id = 12345 in
  let secret = "test-secret" in
  (* HMAC-SHA1: GitHub signs webhooks with HMAC(secret, payload) to
     prove authenticity and prevent tampering *)
  let signature =
    Digestif.SHA1.(to_raw_string (hmac_string ~key:secret payload))
    |> Ohex.encode
    |> fun s -> "sha1=" ^ s
  in
  let headers =
    Header.init ()
    |> fun h ->
    Header.add h "X-GitHub-Event" "pull_request"
    |> fun h -> Header.add h "X-Hub-Signature" signature
  in
  let result = GitHub_subscriptions.receive_github ~secret headers payload in
  match result with
  | Ok (Some parsed_id, _) ->
      Alcotest.(check int) "parses installation.id" install_id parsed_id
  | Ok (None, _) ->
      Alcotest.fail "Should have parsed installation.id"
  | Error msg ->
      Alcotest.fail (Printf.sprintf "Parsing failed: %s" msg)

(* Webhook payload WITHOUT installation.id (legacy webhook format)
   Identical to payload above, except missing the "installation" field.
   Note: After PAT removal, webhooks without installation.id are still accepted
   by receive_github, but any action requiring GitHub API access will fail
   because action_as_github_app requires a GitHub App installation. *)
let payload_without_installation_id =
  {|{
    "action": "opened",
    "repository": {
      "name": "test-repo",
      "owner": {
        "login": "test-owner"
      },
      "html_url": "https://github.com/test-owner/test-repo"
    },
    "pull_request": {
      "number": 1,
      "node_id": "PR_test123",
      "title": "Test PR",
      "html_url": "https://github.com/test-owner/test-repo/pull/1",
      "user": {
        "login": "test-user"
      },
      "labels": [],
      "body": null,
      "assignees": [],
      "base": {
        "ref": "main",
        "sha": "base123",
        "repo": {
          "html_url": "https://github.com/test-owner/test-repo"
        }
      },
      "head": {
        "ref": "feature-branch",
        "sha": "abc123",
        "repo": {
          "html_url": "https://github.com/test-owner/test-repo"
        }
      },
      "merged_at": null
    }
  }|}

let test_webhook_without_installation_id () =
  let secret = "test-secret" in
  (* without installation.id, no signature required *)
  let headers =
    Header.init () |> fun h -> Header.add h "X-GitHub-Event" "pull_request"
  in
  let result =
    GitHub_subscriptions.receive_github ~secret headers
      payload_without_installation_id
  in
  match result with
  | Ok (None, _) ->
      Alcotest.(check bool)
        "Webhook without installation.id accepted by parser (actions will \
         require installation)"
        true true
  | Ok (Some install_id, _) ->
      Alcotest.fail
        (Printf.sprintf "Should not have installation.id, but got: %d"
           install_id )
  | Error msg ->
      Alcotest.fail
        (Printf.sprintf
           "Webhook parsing failed unexpectedly (valid webhook without \
            installation.id should succeed): %s"
           msg )

let () =
  Alcotest.run "Webhook tests"
    [ ( "webhook parsing"
      , [ ("with installation.id", `Quick, test_webhook_with_installation_id)
        ; ( "without installation.id (legacy format accepted, actions require \
             installation)"
          , `Quick
          , test_webhook_without_installation_id ) ] ) ]
