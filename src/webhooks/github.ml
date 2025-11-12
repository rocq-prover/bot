open Base
open Cohttp
open Cohttp_lwt_unix
open Bot_components
open Bot_components.GitHub_types
open Bot_components.GitHub_GitLab_sync
open Bench
open Helpers
open String_utils
open Utils
open Lwt.Infix
open Repo_config

(* Handles push events for repositories with config (fallback handler) *)
let handle_push_event_for_repos ~bot_info ~key ~app_id ~install_id
    ~repo_config_table ~owner ~repo ~base_ref ~head_sha =
  (* Refactored to remove hardcoded repository checks

     Before: Had hardcoded pattern matching for "rocq-community", "math-comp", "rocq-prover".
     Now: Only uses repo_config (no hardcoded fallback). *)
  match get_repo_config_opt ~owner ~repo repo_config_table with
  | Some config -> (
    (* Use the GitLab domain/owner/repo from config *)
    match (config.gitlab_domain, config.gitlab_owner, config.gitlab_repo) with
    | Some domain, Some gl_owner, Some gl_repo ->
        (fun () ->
          init_git_bare_repository ~bot_info
          >>= fun () ->
          Bot_components.Github_installations
          .action_as_github_app_from_install_id ~bot_info ~key ~app_id
            ~install_id
            (mirror_action ~gitlab_domain:domain ~gh_owner:owner ~gh_repo:repo
               ~gl_owner ~gl_repo ~base_ref ~head_sha () ) )
        |> Lwt.async ;
        Server.respond_string ~status:`OK
          ~body:
            (f
               "Processing push event on %s/%s repository: mirroring branch on \
                GitLab."
               owner repo )
          ()
    | _ ->
        Server.respond_string ~status:`OK ~body:"Ignoring push event." () )
  | None ->
      (* No config - ignore event (repos should have config for this feature) *)
      Server.respond_string ~status:`OK ~body:"Ignoring push event." ()

(* Handles all comment-related events (minimization, CI commands, bench commands, etc.)*)
let handle_comment_created ~bot_info ~key ~app_id ~github_bot_name
    ~gitlab_mapping ~github_mapping ~install_id ~repo_config_table
    ~(comment_info : Bot_components.GitHub_types.comment_info)
    ~minimize_text_of_body ~ci_minimize_text_of_body
    ~resume_ci_minimize_text_of_body =
  let body =
    comment_info.body |> trim_comments |> strip_quoted_bot_name ~github_bot_name
  in
  let owner = comment_info.issue.issue.owner in
  let repo = comment_info.issue.issue.repo in
  let repo_config = get_repo_config_opt ~owner ~repo repo_config_table in
  (* Original: hardcoded minimizer URL "https://github.com/rocq-community/run-coq-bug-minimizer/actions"
     Now: use repo_config.minimizer_url if available, fallback to hardcoded value *)
  let minimizer_url =
    match repo_config with
    | Some config -> (
      match config.minimizer_url with
      | Some url ->
          url
      | None ->
          "https://github.com/rocq-community/run-coq-bug-minimizer/actions" )
    | None ->
        "https://github.com/rocq-community/run-coq-bug-minimizer/actions"
  in
  match minimize_text_of_body body with
  | Some (options, script) ->
      (fun () ->
        init_git_bare_repository ~bot_info
        >>= fun () ->
        Bot_components.Github_installations.action_as_github_app ~bot_info ~key
          ~app_id ~owner (fun ~bot_info ->
            Minimization.run_coq_minimizer ~bot_info ~script
              ~comment_thread_id:comment_info.issue.id
              ~comment_author:comment_info.author ~owner ~repo ~options
              ~minimizer_url ) )
      |> Lwt.async ;
      Server.respond_string ~status:`OK ~body:"Handling minimization." ()
  | None -> (
    (* Since both ci minimization resumption and ci
       minimization will match the resumption string, and we
       don't want to parse "resume" as an option, we test
       resumption first *)
    match resume_ci_minimize_text_of_body body with
    | Some (options, requests, bug_file) ->
        (fun () ->
          init_git_bare_repository ~bot_info
          >>= fun () ->
          Bot_components.Github_installations.action_as_github_app ~bot_info
            ~key ~app_id ~owner:comment_info.issue.issue.owner (fun ~bot_info ->
              Minimization.ci_minimize ~bot_info ~comment_info ~requests
                ~comment_on_error:true ~options ~bug_file:(Some bug_file) ) )
        |> Lwt.async ;
        Server.respond_string ~status:`OK
          ~body:"Handling CI minimization resumption." ()
    | None -> (
      match ci_minimize_text_of_body body with
      | Some (options, requests) ->
          (fun () ->
            init_git_bare_repository ~bot_info
            >>= fun () ->
            Bot_components.Github_installations.action_as_github_app ~bot_info
              ~key ~app_id ~owner:comment_info.issue.issue.owner
              (fun ~bot_info ->
                Minimization.ci_minimize ~bot_info ~comment_info ~requests
                  ~comment_on_error:true ~options ~bug_file:None ) )
          |> Lwt.async ;
          Server.respond_string ~status:`OK ~body:"Handling CI minimization." ()
      | None ->
          (* BEFORE: Had hardcoded check for "rocq-prover"/"rocq" *)
          (* NOW: Only checks if repo has config (feature enabled) *)
          if
            string_match
              ~regexp:
                ( f "@%s:? [Rr]un \\(full\\|light\\|\\) ?[Cc][Ii]"
                @@ Str.quote github_bot_name )
              body
            && comment_info.issue.pull_request
            && has_repo_config ~owner ~repo repo_config_table
            && Option.is_some install_id
          then
            let full_ci =
              match Str.matched_group 1 body with
              | "full" ->
                  Some true
              | "light" ->
                  Some false
              | "" ->
                  None
              | _ ->
                  failwith "Impossible group value."
            in
            init_git_bare_repository ~bot_info
            >>= fun () ->
            Bot_components.Github_installations.action_as_github_app ~bot_info
              ~key ~app_id ~owner:comment_info.issue.issue.owner
              (fun ~bot_info ->
                Pr_sync.run_ci_action ~bot_info ~repo_config_table ~comment_info
                  ?full_ci ~gitlab_mapping ~github_mapping () )
          else if
            string_match
              ~regexp:(f "@%s:? [Mm]erge now" @@ Str.quote github_bot_name)
              body
            && comment_info.issue.pull_request
            && has_repo_config ~owner ~repo repo_config_table
            && Option.is_some install_id
          then (
            (fun () ->
              Bot_components.Github_installations.action_as_github_app ~bot_info
                ~key ~app_id ~owner:comment_info.issue.issue.owner
                (fun ~bot_info ->
                  GitHub_automation.merge_pull_request_action ~bot_info
                    comment_info ) )
            |> Lwt.async ;
            Server.respond_string ~status:`OK
              ~body:(f "Received a request to merge the PR.")
              () )
          else if
            string_match
              ~regexp:(f "@%s:? [Bb]ench native" @@ Str.quote github_bot_name)
              body
            && comment_info.issue.pull_request
            && has_repo_config ~owner ~repo repo_config_table
            && Option.is_some install_id
          then (
            (fun () ->
              Bot_components.Github_installations.action_as_github_app ~bot_info
                ~key ~app_id ~owner:comment_info.issue.issue.owner
                (fun ~bot_info ->
                  run_bench ~bot_info ~repo_config_table
                    ~key_value_pairs:[("coq_native", "yes")]
                    comment_info ) )
            |> Lwt.async ;
            Server.respond_string ~status:`OK
              ~body:(f "Received a request to start the bench.")
              () )
          else if
            string_match
              ~regexp:(f "@%s:? [Bb]ench" @@ Str.quote github_bot_name)
              body
            && comment_info.issue.pull_request
            && has_repo_config ~owner ~repo repo_config_table
            && Option.is_some install_id
          then (
            (fun () ->
              Bot_components.Github_installations.action_as_github_app ~bot_info
                ~key ~app_id ~owner:comment_info.issue.issue.owner
                (fun ~bot_info ->
                  run_bench ~bot_info ~repo_config_table comment_info ) )
            |> Lwt.async ;
            Server.respond_string ~status:`OK
              ~body:(f "Received a request to start the bench.")
              () )
          else
            Server.respond_string ~status:`OK
              ~body:(f "Unhandled comment: %s" body)
              () ) )

let handle_github_webhook ~bot_info ~key ~app_id ~github_bot_name
    ~gitlab_mapping ~github_mapping ~repo_config_table ~github_webhook_secret
    ~headers ~body ~minimize_text_of_body ~ci_minimize_text_of_body
    ~resume_ci_minimize_text_of_body =
  body
  >>= fun body ->
  match
    GitHub_subscriptions.receive_github ~secret:github_webhook_secret headers
      body
  with
  | Ok
      (Some install_id, PushEvent {owner; repo; base_ref; head_sha; commits_msg})
    -> (
      (* Refactored to remove hardcoded repository checks

         Before: Had special case for "rocq-prover"/"rocq" that always ran backport + mirror.
         Now: Uses config-based logic - runs backport + mirror only if repo has gitlab_domain
         configured. Backport also requires github_project_number to be set. *)

      (* NEW: Update installation ID cache from webhook event *)
      (* This enables auto-detection to cache installation IDs without explicit config *)
      Repo_config.update_installation_id ~owner ~repo ~install_id
        repo_config_table ;
      (* Check if repo has config with GitLab domain configured *)
      (* BEFORE: Also checked hardcoded `is_rocq` condition *)
      (* NOW: Only checks config, no hardcoded repository names *)
      match get_repo_config_opt ~owner ~repo repo_config_table with
      | Some config when Option.is_some config.gitlab_domain ->
          (* BEFORE: Used hardcoded "gitlab.inria.fr"/"coq"/"coq" as fallback for rocq-prover/rocq *)
          (* NOW: Uses config values, falls back to "gitlab.com"/owner/repo (generic default) *)
          let gitlab_domain, gl_owner, gl_repo =
            match
              (config.gitlab_domain, config.gitlab_owner, config.gitlab_repo)
            with
            | Some domain, Some gl_owner, Some gl_repo ->
                (domain, gl_owner, gl_repo)
            | _ ->
                (* Generic fallback: use default GitLab domain and same owner/repo as GitHub *)
                ("gitlab.com", owner, repo)
          in
          (fun () ->
            init_git_bare_repository ~bot_info
            >>= fun () ->
            (* BEFORE: Always ran backport action for rocq-prover/rocq *)
            (* NOW: Only runs backport if github_project_number is configured *)
            let backport_action =
              if Option.is_some config.github_project_number then
                Bot_components.Github_installations
                .action_as_github_app_from_install_id ~bot_info ~key ~app_id
                  ~install_id (fun ~bot_info ->
                    Backport.rocq_push_action ~bot_info ~repo_config_table
                      ~owner ~repo ~base_ref ~commits_msg )
              else Lwt.return_unit
            in
            (* Mirror action: syncs GitHub push to GitLab (unchanged logic) *)
            let mirror_action =
              Bot_components.Github_installations
              .action_as_github_app_from_install_id ~bot_info ~key ~app_id
                ~install_id
                (mirror_action ~gitlab_domain ~gh_owner:owner ~gh_repo:repo
                   ~gl_owner ~gl_repo ~base_ref ~head_sha () )
            in
            (* Run both actions in parallel (unchanged) *)
            backport_action <&> mirror_action )
          |> Lwt.async ;
          Server.respond_string ~status:`OK
            ~body:(f "Processing push event for %s/%s." owner repo)
            ()
      | Some _ | None ->
          (* BEFORE: Had special case for rocq-prover/rocq even without config *)
          (* NOW: All repos without config go to handle_push_event_for_repos *)
          (* This function has its own fallback logic for backward compatibility *)
          handle_push_event_for_repos ~bot_info ~key ~app_id ~install_id
            ~repo_config_table ~owner ~repo ~base_ref ~head_sha )
  | Ok (_, PullRequestUpdated (PullRequestClosed, pr_info)) ->
      (fun () ->
        init_git_bare_repository ~bot_info
        >>= fun () ->
        Bot_components.Github_installations.action_as_github_app ~bot_info ~key
          ~app_id ~owner:pr_info.issue.issue.owner
          (GitHub_automation.pull_request_closed_action pr_info ~gitlab_mapping
             ~github_mapping ~remove_milestone_if_not_merged:true ) )
      |> Lwt.async ;
      Server.respond_string ~status:`OK
        ~body:
          (f
             "Pull request %s/%s#%d was closed: removing the branch from \
              GitLab."
             pr_info.issue.issue.owner pr_info.issue.issue.repo
             pr_info.issue.issue.number )
        ()
  | Ok (_, PullRequestUpdated (action, pr_info)) ->
      init_git_bare_repository ~bot_info
      >>= fun () ->
      Pr_sync.pull_request_updated_action ~bot_info ~repo_config_table ~action
        ~pr_info ~gitlab_mapping ~github_mapping
  | Ok (_, IssueClosed {issue}) ->
      (* TODO: only for projects that requested this feature *)
      (fun () ->
        Bot_components.Github_installations.action_as_github_app ~bot_info ~key
          ~app_id ~owner:issue.owner (fun ~bot_info ->
            GitHub_automation.adjust_milestone ~bot_info ~issue ~sleep_time:5. )
        )
      |> Lwt.async ;
      Server.respond_string ~status:`OK
        ~body:
          (f "Issue %s/%s#%d was closed: checking its milestone." issue.owner
             issue.repo issue.number )
        ()
  | Ok
      ( Some install_id
      , PullRequestCardEdited
          { project_number
          ; pr_id
          ; field
          ; old_value= Some "Request inclusion"
          ; new_value= Some "Rejected" } )
    when String.is_suffix ~suffix:" status" field ->
      (* BEFORE: Had hardcoded check for "rocq-prover"/"rocq" with install_id=1062161 and project_number=11 *)
      (* NOW: Check if install_id and project_number match any repo_config *)
      let matches_config =
        (* Search all repos in config table for matching install_id and project_number *)
        Hashtbl.fold repo_config_table ~init:false
          ~f:(fun ~key:_ ~data:config acc ->
            acc
            ||
            match
              (config.github_installation_id, config.github_project_number)
            with
            | Some config_install_id, Some config_project_number ->
                Int.equal install_id config_install_id
                && Int.equal project_number config_project_number
            | _ ->
                false )
      in
      if matches_config then (
        let backport_to = String.drop_suffix field 7 in
        (fun () ->
          Bot_components.Github_installations
          .action_as_github_app_from_install_id ~bot_info ~key ~app_id
            ~install_id (fun ~bot_info ->
              GitHub_automation.project_action ~bot_info ~pr_id ~backport_to () )
          )
        |> Lwt.async ;
        Server.respond_string ~status:`OK
          ~body:
            (f
               "PR proposed for backporting was rejected from inclusion in %s. \
                Updating the milestone."
               backport_to )
          () )
      else
        Server.respond_string ~status:`OK
          ~body:"Unsupported pull request card edition." ()
  | Ok (_, PullRequestCardEdited _) ->
      Server.respond_string ~status:`OK
        ~body:"Unsupported pull request card edition." ()
  | Ok (_, IssueOpened ({body= Some body} as issue_info)) -> (
      let body =
        body |> trim_comments |> strip_quoted_bot_name ~github_bot_name
      in
      match minimize_text_of_body body with
      | Some (options, script) ->
          (fun () ->
            init_git_bare_repository ~bot_info
            >>= fun () ->
            Bot_components.Github_installations.action_as_github_app ~bot_info
              ~key ~app_id ~owner:issue_info.issue.owner (fun ~bot_info ->
                Minimization.run_coq_minimizer ~bot_info ~script
                  ~comment_thread_id:issue_info.id
                  ~comment_author:issue_info.user ~owner:issue_info.issue.owner
                  ~repo:issue_info.issue.repo ~options
                  ~minimizer_url:
                    "https://github.com/rocq-community/run-coq-bug-minimizer/actions" )
            )
          |> Lwt.async ;
          Server.respond_string ~status:`OK ~body:"Handling minimization." ()
      | None ->
          Server.respond_string ~status:`OK
            ~body:(f "Unhandled new issue: %s" body)
            () )
  | Ok (install_id, CommentCreated comment_info) ->
      handle_comment_created ~bot_info ~key ~app_id ~github_bot_name
        ~gitlab_mapping ~github_mapping ~install_id ~repo_config_table
        ~comment_info ~minimize_text_of_body ~ci_minimize_text_of_body
        ~resume_ci_minimize_text_of_body
  | Ok (None, CheckRunReRequested _) ->
      Server.respond_string ~status:(Code.status_of_code 401)
        ~body:"Request to rerun check run must be signed." ()
  | Ok (Some _, CheckRunReRequested {external_id}) -> (
      if String.is_empty external_id then
        Server.respond_string ~status:(Code.status_of_code 400)
          ~body:"Request to rerun check run but empty external ID." ()
      else
        let external_id_parsed =
          Minimize_parser.parse_check_run_external_id external_id
        in
        match external_id_parsed with
        | None ->
            Server.respond_string ~status:(Code.status_of_code 400)
              ~body:
                (f
                   "Request to rerun check run but external ID is not \
                    well-formed: %s"
                   external_id )
              ()
        | Some (gitlab_domain, url_part) ->
            (fun () ->
              GitLab_mutations.generic_retry ~bot_info ~gitlab_domain ~url_part
              )
            |> Lwt.async ;
            Server.respond_string ~status:`OK
              ~body:
                (f
                   "Received a request to re-run a job / pipeline (External ID \
                    : %s)."
                   external_id )
              () )
  | Ok (_, UnsupportedEvent s) ->
      Server.respond_string ~status:`OK ~body:(f "No action taken: %s" s) ()
  | Ok _ ->
      Server.respond_string ~status:`OK
        ~body:"No action taken: event or action is not yet supported." ()
  | Error ("Webhook signed but with wrong signature." as e) ->
      (fun () -> Lwt_io.printl e) |> Lwt.async ;
      Server.respond_string ~status:(Code.status_of_code 401)
        ~body:(f "Error: %s" e) ()
  | Error e ->
      Server.respond_string ~status:(Code.status_of_code 400)
        ~body:(f "Error: %s" e) ()
