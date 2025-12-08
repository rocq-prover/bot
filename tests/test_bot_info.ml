open Bot_components
open Base

(* Test helper: Create bot_info with specific configuration *)
let create_bot_info ~github_install_token ~github_pat =
  { Bot_info.github_install_token
  ; github_pat
  ; github_name= "testbot"
  ; email= "test@example.com"
  ; domain= "test.com"
  ; gitlab_instances= Hashtbl.create (module String)
  ; app_id= 12345 }

let test_github_pat_returns_value () =
  let bot_info =
    create_bot_info ~github_install_token:"install_token_123"
      ~github_pat:(Some "pat_123")
  in
  let pat = Bot_info.github_pat bot_info in
  Alcotest.(check string) "returns PAT when present" "pat_123" pat

let test_github_pat_missing () =
  let bot_info =
    create_bot_info ~github_install_token:"install_token_123" ~github_pat:None
  in
  match Result.try_with (fun () -> Bot_info.github_pat bot_info) with
  | Ok _ ->
      Alcotest.fail "Expected github_pat to raise when missing"
  | Error _ ->
      ()

let () =
  Alcotest.run "Bot_info tests"
    [ ( "github_pat"
      , [ ( "returns GitHub PAT when available"
          , `Quick
          , test_github_pat_returns_value )
        ; ( "fails when no PAT is configured"
          , `Quick
          , test_github_pat_missing ) ] ) ]
