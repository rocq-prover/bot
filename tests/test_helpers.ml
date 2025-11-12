open Base
open Bot_components

(** Create a mock bot_info for testing *)
let create_mock_bot_info () =
  let gitlab_instances = Hashtbl.create (module String) in
  Hashtbl.set gitlab_instances ~key:"gitlab.com"
    ~data:("test-name", "test-token") ;
  { Bot_info.github_pat= "test-token"
  ; github_install_token= None
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
        { Bot_info.github_pat= token
        ; github_install_token= None
        ; gitlab_instances
        ; github_name= "test-bot"
        ; email= "test-bot@users.noreply.github.com"
        ; domain= "test-bot.herokuapp.com"
        ; app_id= 12345
        ; api_timeout= 5.0 }
