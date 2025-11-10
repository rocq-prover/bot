open Base
open Cohttp
open Cohttp_lwt_unix
open Bot_components
open Utils
open Lwt.Infix

let handle_stale_pr_check ~bot_info ~key ~app_id ~daily_schedule_secret ~body =
  body
  >>= fun body ->
  match String.split ~on:':' body with
  | [owner; repo; secret] ->
      if String.equal secret daily_schedule_secret then (
        let warn_after = 30 in
        let close_after = 30 in
        (fun () ->
          Bot_components.Github_installations.action_as_github_app ~bot_info
            ~key ~app_id ~owner
            (Pr_sync.rocq_check_needs_rebase_pr ~owner ~repo ~warn_after
               ~close_after ~throttle:6 )
          >>= fun () ->
          Bot_components.Github_installations.action_as_github_app ~bot_info
            ~key ~app_id ~owner
            (Pr_sync.rocq_check_stale_pr ~owner ~repo ~after:close_after
               ~throttle:4 ) )
        |> Lwt.async ;
        Server.respond_string ~status:`OK ~body:"Stale pull requests updated" ()
        )
      else
        Server.respond_error ~status:`Unauthorized ~body:"Incorrect secret" ()
  | _ ->
      Server.respond_string ~status:(Code.status_of_code 400)
        ~body:(f "Error: ill-formed request")
        ()
