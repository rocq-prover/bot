open Bot_components
open Base

(* Test helper: Create bot_info with specific configuration *)
let create_bot_info ~github_install_token =
  { Bot_info.github_install_token
  ; github_name= "testbot"
  ; email= "test@example.com"
  ; domain= "test.com"
  ; gitlab_instances= Hashtbl.create (module String)
  ; app_id= 12345 }

let test_uses_github_app_token_when_available () =
  let bot_info =
    create_bot_info ~github_install_token:(Some "install_token_123")
  in
  let token = Bot_info.github_token bot_info in
  Alcotest.(check string) "uses installation token" "install_token_123" token

(* When no installation token exists, github_token should fail (PAT removed) *)
let test_fails_when_no_installation_token () =
  let bot_info = create_bot_info ~github_install_token:None in
  try
    let _ = Bot_info.github_token bot_info in
    Alcotest.fail "Should have failed but returned a token"
  with
  | Failure msg when String.is_substring msg ~substring:"installation token" ->
      ()
  | exn ->
      Alcotest.fail (Printf.sprintf "Wrong exception: %s" (Exn.to_string exn))

let () =
  Alcotest.run "Bot_info tests"
    [ ( "github_token"
      , [ ( "uses GitHub App token when available"
          , `Quick
          , test_uses_github_app_token_when_available )
        ; ( "fails when no installation token"
          , `Quick
          , test_fails_when_no_installation_token ) ] ) ]
