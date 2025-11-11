open Base
open Cohttp
open Cohttp_lwt_unix
open Bot_components
open Bot_components.GitHub_GitLab_sync
open Job_status
open Lwt.Infix
open Utils
open Repo_config

let handle_gitlab_webhook ~bot_info ~key ~app_id ~gitlab_mapping
    ~repo_config_table ~gitlab_webhook_secret ~headers ~body =
  body
  >>= fun body ->
  match
    GitLab_subscriptions.receive_gitlab ~secret:gitlab_webhook_secret headers
      body
  with
  | Ok (_, JobEvent ({common_info= {http_repo_url}} as job_info)) -> (
    match github_repo_of_gitlab_url ~gitlab_mapping ~http_repo_url with
    | Error error_msg ->
        (fun () -> Lwt_io.printl error_msg) |> Lwt.async ;
        Server.respond_string ~status:`Bad_request ~body:error_msg ()
    | Ok (owner, _) ->
        (fun () ->
          Bot_components.Github_installations.action_as_github_app ~bot_info
            ~key ~app_id ~owner (fun ~bot_info ->
              Job.job_action ~bot_info ~repo_config_table ~gitlab_mapping
                job_info ) )
        |> Lwt.async ;
        Server.respond_string ~status:`OK ~body:"Job event." () )
  | Ok (_, PipelineEvent ({common_info= {http_repo_url}} as pipeline_info)) -> (
    match github_repo_of_gitlab_url ~gitlab_mapping ~http_repo_url with
    | Error error_msg ->
        (fun () -> Lwt_io.printl error_msg) |> Lwt.async ;
        Server.respond_string ~status:`Bad_request ~body:error_msg ()
    | Ok (owner, _) ->
        (fun () ->
          Bot_components.Github_installations.action_as_github_app ~bot_info
            ~key ~app_id ~owner (fun ~bot_info ->
              (* Original: hardcoded "rocq-prover", "rocq" for full_ci_check_repo and auto_minimize_on_failure
                 Now: use repo_config if available, fallback to hardcoded values *)
              let full_ci_repo =
                Option.first_some
                  (find_repo_with_ci_config repo_config_table)
                  (Some ("rocq-prover", "rocq"))
              in
              let minimizer_repo =
                Option.first_some
                  (find_repo_with_minimizer repo_config_table)
                  (Some ("rocq-prover", "rocq"))
              in
              pipeline_action ~bot_info ~repo_config_table pipeline_info
                ~gitlab_mapping ~full_ci_check_repo:full_ci_repo
                ~auto_minimize_on_failure:minimizer_repo () ) )
        |> Lwt.async ;
        Server.respond_string ~status:`OK ~body:"Pipeline event." () )
  | Ok (_, UnsupportedEvent e) ->
      Server.respond_string ~status:`OK ~body:(f "Unsupported event %s." e) ()
  | Error ("Webhook password mismatch." as e) ->
      (fun () -> Lwt_io.printl e) |> Lwt.async ;
      Server.respond_string ~status:(Code.status_of_code 401)
        ~body:(f "Error: %s" e) ()
  | Error e ->
      Server.respond_string ~status:(Code.status_of_code 400)
        ~body:(f "Error: %s" e) ()
