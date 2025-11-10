open Cohttp
open Cohttp_lwt_unix
open Bot_components
open Utils
open Lwt.Infix

let handle_minimizer_webhook ~bot_info ~key ~app_id ~endpoint ~body =
  body
  >>= fun body ->
  match endpoint with
  | "/coq-bug-minimizer" ->
      Minimization.coq_bug_minimizer_results_action ~ci:false body ~bot_info
        ~key ~app_id
  | "/ci-minimization" ->
      Minimization.coq_bug_minimizer_results_action ~ci:true body ~bot_info ~key
        ~app_id
  | "/resume-ci-minimization" ->
      Minimization.coq_bug_minimizer_resume_ci_minimization_action body
        ~bot_info ~key ~app_id
  | _ ->
      Server.respond_string ~status:(Code.status_of_code 404)
        ~body:(f "Unknown minimizer endpoint: %s" endpoint)
        ()
