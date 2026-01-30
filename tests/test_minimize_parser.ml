open Base
open Minimize_parser

let github_bot_name = "coqbot"

(* Helper to check if minimize parsing succeeds *)
let test_minimize_parses ~name ~body ~expected_options ~expected_quote_kind =
  match parse_minimize_text_of_body ~github_bot_name body with
  | None ->
      Alcotest.failf "%s: expected parse to succeed, but got None" name
  | Some (options, MinimizeScript {quote_kind; _}) ->
      let trimmed_options = String.strip options in
      let trimmed_expected = String.strip expected_options in
      if
        String.equal trimmed_options trimmed_expected
        && String.equal quote_kind expected_quote_kind
      then ()
      else
        Alcotest.failf
          "%s: expected options='%s' quote_kind='%s', got options='%s' \
           quote_kind='%s'"
          name expected_options expected_quote_kind options quote_kind
  | Some (_, MinimizeAttachment _) ->
      Alcotest.failf "%s: expected MinimizeScript, got MinimizeAttachment" name

let test_minimize_does_not_parse ~name ~body =
  match parse_minimize_text_of_body ~github_bot_name body with
  | None ->
      ()
  | Some _ ->
      Alcotest.failf "%s: expected parse to fail, but it succeeded" name

(* Test: Basic minimize with options and code block *)
let test_basic_minimize () =
  let body = "@coqbot minimize coq=9.1\n```bash\necho test\n```" in
  test_minimize_parses ~name:"basic minimize" ~body ~expected_options:"coq=9.1"
    ~expected_quote_kind:"bash"

(* Test: Minimize with no options *)
let test_minimize_no_options () =
  let body = "@coqbot minimize\n```bash\n#!/usr/bin/env bash\nopam install\n```" in
  test_minimize_parses ~name:"minimize no options" ~body ~expected_options:""
    ~expected_quote_kind:"bash"

(* Test: Minimize with preceding text on separate line *)
let test_minimize_preceding_text () =
  let body = "Some text\n\n@coqbot minimize\n```bash\ntest\n```" in
  test_minimize_parses ~name:"preceding text" ~body ~expected_options:""
    ~expected_quote_kind:"bash"

(* Test: Minimize with preceding text on same line *)
let test_minimize_same_line_text () =
  let body = "Check: @coqbot minimize coq.dev\n```bash\ntest\n```" in
  test_minimize_parses ~name:"same line text" ~body ~expected_options:"coq.dev"
    ~expected_quote_kind:"bash"

(* Test: Minimize with colon after bot name *)
let test_minimize_with_colon () =
  let body = "@coqbot: minimize coq=9.1\n```bash\ntest\n```" in
  test_minimize_parses ~name:"with colon" ~body ~expected_options:"coq=9.1"
    ~expected_quote_kind:"bash"

(* Test: The exact failing case from the issue *)
let test_minimize_issue_case () =
  let body =
    "@coqbot minimize\n```bash\n#!/usr/bin/env bash\nopam install -y \
     coq-fiat-crypto\n```"
  in
  test_minimize_parses ~name:"issue case" ~body ~expected_options:""
    ~expected_quote_kind:"bash"

(* Test: Minimize without code block should fail *)
let test_minimize_no_code_block () =
  let body = "@coqbot minimize coq=9.1" in
  test_minimize_does_not_parse ~name:"no code block" ~body

(* Test: CI minimize basic *)
let test_ci_minimize_basic () =
  match parse_ci_minimize_text_of_body ~github_bot_name "@coqbot ci minimize" with
  | None ->
      Alcotest.fail "ci minimize basic: expected parse to succeed"
  | Some (_, requests) when List.is_empty requests ->
      ()
  | Some (_, requests) ->
      Alcotest.failf "ci minimize basic: expected empty requests, got %d"
        (List.length requests)

(* Test: CI minimize with requests *)
let test_ci_minimize_with_requests () =
  match
    parse_ci_minimize_text_of_body ~github_bot_name "@coqbot ci minimize job1 job2"
  with
  | None ->
      Alcotest.fail "ci minimize with requests: expected parse to succeed"
  | Some (_, requests) ->
      let expected = ["job1"; "job2"] in
      if List.equal String.equal requests expected then ()
      else
        Alcotest.failf "ci minimize with requests: expected [job1; job2], got [%s]"
          (String.concat ~sep:"; " requests)

(* Test: CI-minimize (hyphenated) *)
let test_ci_minimize_hyphenated () =
  match
    parse_ci_minimize_text_of_body ~github_bot_name "@coqbot CI-minimize job1"
  with
  | None ->
      Alcotest.fail "ci-minimize hyphenated: expected parse to succeed"
  | Some (_, requests) ->
      let expected = ["job1"] in
      if List.equal String.equal requests expected then ()
      else
        Alcotest.failf "ci-minimize hyphenated: expected [job1], got [%s]"
          (String.concat ~sep:"; " requests)

(* Test: CI minimize should not match regular minimize *)
let test_ci_minimize_not_regular () =
  match
    parse_ci_minimize_text_of_body ~github_bot_name
      "@coqbot minimize\n```bash\ntest\n```"
  with
  | None ->
      () (* expected - regular minimize should not match ci minimize pattern *)
  | Some _ ->
      Alcotest.fail "ci minimize should not match regular minimize syntax"

let () =
  Alcotest.run "Minimize_parser tests"
    [ ( "parse_minimize_text_of_body"
      , [ ("basic minimize", `Quick, test_basic_minimize)
        ; ("minimize no options", `Quick, test_minimize_no_options)
        ; ("preceding text", `Quick, test_minimize_preceding_text)
        ; ("same line text", `Quick, test_minimize_same_line_text)
        ; ("with colon", `Quick, test_minimize_with_colon)
        ; ("issue case", `Quick, test_minimize_issue_case)
        ; ("no code block", `Quick, test_minimize_no_code_block) ] )
    ; ( "parse_ci_minimize_text_of_body"
      , [ ("basic ci minimize", `Quick, test_ci_minimize_basic)
        ; ("ci minimize with requests", `Quick, test_ci_minimize_with_requests)
        ; ("ci-minimize hyphenated", `Quick, test_ci_minimize_hyphenated)
        ; ("not regular minimize", `Quick, test_ci_minimize_not_regular) ] ) ]
