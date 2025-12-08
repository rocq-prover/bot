open Base
open Cohttp_lwt_unix
open Bot_components
open Bot_components.Minimize_parser

let toml_data = Utils.toml_of_file (Sys.get_argv ()).(1)

let port = Config.port toml_data

let github_webhook_secret = Config.github_webhook_secret toml_data

(* TODO: make webhook secret project-specific *)
let gitlab_webhook_secret = Config.gitlab_webhook_secret toml_data

let daily_schedule_secret = Config.daily_schedule_secret toml_data

let github_bot_name = Config.github_bot_name toml_data

let key = Config.github_private_key ()

let app_id = Config.github_app_id toml_data

let bot_info : Bot_components.Bot_info.t =
  { github_install_token= ""
  ; github_pat= None
  ; gitlab_instances= Config.gitlab_instances toml_data
  ; github_name= github_bot_name
  ; email= Config.bot_email toml_data
  ; domain= Config.bot_domain toml_data
  ; app_id }

let github_mapping, gitlab_mapping = Config.make_mappings_table toml_data

(* TODO: deprecate unsigned webhooks *)

let callback _conn req body =
  let minimize_text_of_body = parse_minimize_text_of_body ~github_bot_name in
  let ci_minimize_text_of_body =
    parse_ci_minimize_text_of_body ~github_bot_name
  in
  let resume_ci_minimize_text_of_body =
    parse_resume_ci_minimize_text_of_body ~github_bot_name
  in
  let body = Cohttp_lwt.Body.to_string body in
  let path = Uri.path (Request.uri req) in
  (* print_endline "Request received."; *)
  match path with
  | "/job" | "/pipeline" (* legacy endpoints *) | "/gitlab" ->
      Webhook_gitlab.handle_gitlab_webhook ~bot_info ~key ~app_id
        ~gitlab_mapping ~gitlab_webhook_secret ~headers:(Request.headers req)
        ~body
  | "/push" | "/pull_request" (* legacy endpoints *) | "/github" ->
      Webhook_github.handle_github_webhook ~bot_info ~key ~app_id
        ~github_bot_name ~gitlab_mapping ~github_mapping ~github_webhook_secret
        ~headers:(Request.headers req) ~body ~minimize_text_of_body
        ~ci_minimize_text_of_body ~resume_ci_minimize_text_of_body
  | "/coq-bug-minimizer" | "/ci-minimization" | "/resume-ci-minimization" ->
      Webhook_minimizer.handle_minimizer_webhook ~bot_info ~key ~app_id
        ~endpoint:path ~body
  | "/check-stale-pr" ->
      Webhook_scheduled.handle_stale_pr_check ~bot_info ~key ~app_id
        ~daily_schedule_secret ~body
  | _ ->
      Server.respond_not_found ()

let launch =
  let mode = `TCP (`Port port) in
  Server.create ~mode (Server.make ~callback ())

let () =
  Lwt.async_exception_hook :=
    fun exn ->
      (fun () ->
        Lwt_io.printlf "Error: Unhandled exception: %s" (Exn.to_string exn) )
      |> Lwt.async

(* RNG seeding: https://github.com/mirage/mirage-crypto#faq *)
let () = Mirage_crypto_rng_unix.use_default ()

let () = Lwt_main.run launch
