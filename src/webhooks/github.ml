open Base
open Cohttp
open Cohttp_lwt_unix
open Bot_components
open Bot_components.GitHub_types
open Bot_components.GitHub_GitLab_sync
open Git_utils
open String_utils
open Utils
open Lwt.Infix

(* Handles push events for different repositories (e.g., Rocq community, Math Comp, etc.) *)
let handle_push_event_for_repos ~bot_info ~key ~app_id ~install_id ~owner ~repo
    ~base_ref ~head_sha =
  match (owner, repo) with
  | "rocq-community", ("docker-base" | "docker-coq" | "docker-rocq") ->
      (fun () ->
        init_git_bare_repository ~bot_info
        >>= fun () ->
        Bot_components.Github_installations.action_as_github_app_from_install_id
          ~bot_info ~key ~app_id ~install_id
          (mirror_action ~gitlab_domain:"gitlab.com" ~gh_owner:owner
             ~gh_repo:repo ~gl_owner:owner ~gl_repo:repo ~base_ref ~head_sha () ) )
      |> Lwt.async ;
      Server.respond_string ~status:`OK
        ~body:
          (f
             "Processing push event on %s/%s repository: mirroring branch on \
              GitLab."
             owner repo )
        ()
  | "math-comp", ("docker-mathcomp" | "math-comp") ->
      (fun () ->
        init_git_bare_repository ~bot_info
        >>= fun () ->
        Bot_components.Github_installations.action_as_github_app_from_install_id
          ~bot_info ~key ~app_id ~install_id
          (mirror_action ~gitlab_domain:"gitlab.inria.fr" ~gh_owner:owner
             ~gh_repo:repo ~gl_owner:owner ~gl_repo:repo ~base_ref ~head_sha () ) )
      |> Lwt.async ;
      Server.respond_string ~status:`OK
        ~body:
          (f
             "Processing push event on %s/%s repository: mirroring branch on \
              GitLab."
             owner repo )
        ()
  | "rocq-prover", ("opam" | "docker-rocq") ->
      (fun () ->
        init_git_bare_repository ~bot_info
        >>= fun () ->
        Bot_components.Github_installations.action_as_github_app_from_install_id
          ~bot_info ~key ~app_id ~install_id
          (mirror_action ~gitlab_domain:"gitlab.inria.fr"
             ~gh_owner:"rocq-prover" ~gh_repo:repo ~gl_owner:"coq" ~gl_repo:repo
             ~base_ref ~head_sha () ) )
      |> Lwt.async ;
      Server.respond_string ~status:`OK
        ~body:
          (f
             "Processing push event on %s/%s repository: mirroring branch on \
              GitLab."
             owner repo )
        ()
  | _ ->
      Server.respond_string ~status:`OK ~body:"Ignoring push event." ()

module Commands = struct

  type bench_args = (string * string option) list

  type t =
    | RunCI of { full_ci : bool option }
    | Merge
    | Bench of bench_args
    | ResumeMinimize of (string * string list * Minimize_parser.minimize_parsed)
    | Minimize of (string * string list)
end

open Commands

(* Handles all comment-related events (minimization, CI commands, bench commands, etc.)*)
let handle_comment_created ~bot_info ~key ~app_id ~github_bot_name
    ~gitlab_mapping ~github_mapping ~install_id
    ~(comment_info : Bot_components.GitHub_types.comment_info)
    ~minimize_text_of_body ~ci_minimize_text_of_body
    ~resume_ci_minimize_text_of_body =
  let body =
    comment_info.body |> trim_comments |> strip_quoted_bot_name ~github_bot_name
  in
  match minimize_text_of_body body with
  | Some (options, script) ->
      (fun () ->
        init_git_bare_repository ~bot_info
        >>= fun () ->
        Bot_components.Github_installations.action_as_github_app ~bot_info ~key
          ~app_id ~owner:comment_info.issue.issue.owner (fun ~bot_info ->
            Minimization.run_coq_minimizer ~bot_info ~script
              ~comment_thread_id:comment_info.issue.id
              ~comment_author:comment_info.author
              ~owner:comment_info.issue.issue.owner
              ~repo:comment_info.issue.issue.repo ~options
              ~minimizer_url:
                "https://github.com/rocq-community/run-coq-bug-minimizer/actions" ) )
      |> Lwt.async ;
      Server.respond_string ~status:`OK ~body:"Handling minimization." ()
  | None ->

    let parse_run_ci body =
      if string_match
        ~regexp:
          ( f "@%s:? [Rr]un \\(full\\|light\\|\\) ?[Cc][Ii]"
            @@ Str.quote github_bot_name )
        body
      then
        let full_ci =
          match Str.matched_group 1 body with
          | "full" -> Some true
          | "light" -> Some false
          | "" -> None
          | _ -> failwith "Impossible group value."
        in
        Some (RunCI {full_ci})
      else
        None
    in
   let parse_merge body =
     if string_match
       ~regexp:(f "@%s:? [Mm]erge now" @@ Str.quote github_bot_name)
       body
     then
       Some Merge
     else
       None
    in

    let parse_bench body =
      if
        string_match
          ~regexp:(f {|@%s:? [Bb]ench\( *$\| +\([^\n]+\) *\(\n\|$\)\)|} @@ Str.quote github_bot_name)
          body
      then
        match Str.matched_group 2 body with
        | exception _ -> Some (Bench [])
        | args ->
          match parse_key_value_arguments args with
          | Result.Ok args -> Some (Bench args)
          | _ -> None
      else
        None
    in
    let parse () =
      let open Option in
      let rec first_success body fns =
        match fns with
        | fn :: fns ->
          let res = fn body in
          if Option.is_some res then res else first_success body fns
        | [] -> None
      in
    (* Since both ci minimization resumption and ci minimization will match the
       resumption string, and we don't want to parse "resume" as an option, we
       test resumption first *)
      first_success body [
        (fun body -> resume_ci_minimize_text_of_body body >>| fun x -> ResumeMinimize x);
        (fun body -> ci_minimize_text_of_body body >>| fun x -> Minimize x);
        parse_run_ci;
        parse_merge;
        parse_bench
      ]
    in
    match parse () with
    | Some (ResumeMinimize (options, requests, bug_file)) ->
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
    | Some (Minimize (options, requests)) ->
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
    | Some (RunCI {full_ci}) when
        comment_info.issue.pull_request
        && String.equal comment_info.issue.issue.owner "rocq-prover"
        && String.equal comment_info.issue.issue.repo "rocq"
        && Option.is_some install_id ->
      init_git_bare_repository ~bot_info
      >>= fun () ->
      Bot_components.Github_installations.action_as_github_app ~bot_info
        ~key ~app_id ~owner:comment_info.issue.issue.owner
        (Pr_sync.run_ci_action ~comment_info ?full_ci ~gitlab_mapping
           ~github_mapping () )
    | Some Merge when
        comment_info.issue.pull_request
        && String.equal comment_info.issue.issue.owner "rocq-prover"
        && String.equal comment_info.issue.issue.repo "rocq"
        && Option.is_some install_id ->
      (fun () ->
         Bot_components.Github_installations.action_as_github_app ~bot_info
           ~key ~app_id ~owner:comment_info.issue.issue.owner
           (fun ~bot_info ->
              GitHub_automation.merge_pull_request_action ~bot_info
                comment_info ) )
      |> Lwt.async ;
      Server.respond_string ~status:`OK
        ~body:(f "Received a request to merge the PR.")
        ()
    | Some (Bench args) when
            comment_info.issue.pull_request
            && String.equal comment_info.issue.issue.owner "rocq-prover"
            && String.equal comment_info.issue.issue.repo "rocq"
            && Option.is_some install_id ->
      let key_value_pairs = List.map ~f:(fun (k,v) -> (k, Option.value ~default:"yes" v)) args in
      (fun () ->
         Bot_components.Github_installations.action_as_github_app ~bot_info
           ~key ~app_id ~owner:comment_info.issue.issue.owner
           (fun ~bot_info ->
              Bench.run_bench ~bot_info
                ~key_value_pairs
                comment_info )
      )
      |> Lwt.async ;
      Server.respond_string ~status:`OK
        ~body:(f "Received a request to start the bench.")
        ()
    | _ ->
      Server.respond_string ~status:`OK
        ~body:(f "Unhandled comment: %s" body)
        ()

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
      ( Some install_id
      , PushEvent
          {owner= "rocq-prover"; repo= "rocq"; base_ref; head_sha; commits_msg}
      ) ->
      (fun () ->
        init_git_bare_repository ~bot_info
        >>= fun () ->
        let backport =
          match
            Repo_config.find_by_github ~owner:"rocq-prover" ~repo:"rocq"
              repo_config_table
          with
          | Some cfg when Repo_config.backport_enabled cfg ->
              Bot_components.Github_installations
              .action_as_github_app_from_install_id ~bot_info ~key ~app_id
                ~install_id
                (Backport.push_action ~repo_config:cfg ~base_ref ~commits_msg)
          | _ ->
              Lwt.return_unit
        in
        backport
        <&> Bot_components.Github_installations
            .action_as_github_app_from_install_id ~bot_info ~key ~app_id
              ~install_id
              (mirror_action ~gitlab_domain:"gitlab.inria.fr"
                 ~gh_owner:"rocq-prover" ~gh_repo:"rocq" ~gl_owner:"coq"
                 ~gl_repo:"coq" ~base_ref ~head_sha () ) )
      |> Lwt.async ;
      Server.respond_string ~status:`OK
        ~body:
          "Processing push event on the Rocq Prover repository: analyzing \
           merge / backporting info."
        ()
  | Ok (Some install_id, PushEvent {owner; repo; base_ref; head_sha; _}) ->
      handle_push_event_for_repos ~bot_info ~key ~app_id ~install_id ~owner
        ~repo ~base_ref ~head_sha
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
      Bot_components.Github_installations.action_as_github_app ~bot_info ~key
        ~app_id ~owner:pr_info.issue.issue.owner
        (Pr_sync.pull_request_updated_action ~action ~pr_info ~gitlab_mapping
           ~github_mapping )
  | Ok (_, IssueClosed {issue}) ->
      (* TODO: only for projects that requested this feature *)
      (fun () ->
        Bot_components.Github_installations.action_as_github_app ~bot_info ~key
          ~app_id ~owner:issue.owner (fun ~bot_info ->
            GitHub_automation.adjust_milestone ~bot_info ~issue ~sleep_time:5. ) )
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
    when String.is_suffix ~suffix:" status" field -> (
    match
      Repo_config.find_by_backport_project ~install_id ~project_number
        repo_config_table
    with
    | None ->
        Server.respond_string ~status:`OK
          ~body:
            "Pull request card edition ignored: backporting project not \
             configured."
          ()
    | Some repo_config ->
        (* Field matches "<branch> status" (checked above); drop " status". *)
        let backport_to = String.drop_suffix field 7 in
        (fun () ->
          Bot_components.Github_installations
          .action_as_github_app_from_install_id ~bot_info ~key ~app_id
            ~install_id (fun ~bot_info ->
              Backport.project_action ~bot_info ~repo_config ~pr_id ~backport_to
                () ) )
        |> Lwt.async ;
        Server.respond_string ~status:`OK
          ~body:
            (f
               "PR proposed for backporting was rejected from inclusion in %s. \
                Updating the milestone."
               backport_to )
          () )
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
                    "https://github.com/rocq-community/run-coq-bug-minimizer/actions" ) )
          |> Lwt.async ;
          Server.respond_string ~status:`OK ~body:"Handling minimization." ()
      | None ->
          Server.respond_string ~status:`OK
            ~body:(f "Unhandled new issue: %s" body)
            () )
  | Ok (install_id, CommentCreated comment_info) ->
      handle_comment_created ~bot_info ~key ~app_id ~github_bot_name
        ~gitlab_mapping ~github_mapping ~install_id ~comment_info
        ~minimize_text_of_body ~ci_minimize_text_of_body
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
              GitLab_mutations.generic_retry ~bot_info ~gitlab_domain ~url_part )
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
