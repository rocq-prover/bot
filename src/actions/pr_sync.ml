open Base
open Bot_components
open Bot_components.Bot_info
open Bot_components.GitHub_types
open Bot_components.GitHub_GitLab_sync
open Cohttp_lwt_unix
open Git_utils
open Utils
open Lwt.Infix
open Repo_config

(* TODO: ensure there's no race condition for 2 push with very close timestamps *)
let update_pr ?full_ci ?(skip_author_check = false) ~bot_info ~repo_config_table
    (pr_info : issue_info pull_request_info) ~gitlab_mapping ~github_mapping =
  let open Lwt_result.Infix in
  (* Try as much as possible to get unique refnames for local branches. *)
  let local_head_branch =
    f "head-%s-%s" pr_info.head.branch.name pr_info.head.sha
  in
  let local_base_branch =
    f "base-%s-%s" pr_info.base.branch.name pr_info.base.sha
  in
  git_fetch pr_info.base.branch ("refs/heads/" ^ local_base_branch)
  |&& git_fetch pr_info.head.branch ("refs/heads/" ^ local_head_branch)
  |> execute_cmd
  >>= (fun () ->
        git_make_ancestor ~pr_title:pr_info.issue.title
          ~pr_number:pr_info.issue.number ~base:local_base_branch
          local_head_branch )
  >>= fun ok ->
  let owner = pr_info.issue.issue.owner in
  let repo = pr_info.issue.issue.repo in
  let repo_config = get_repo_config_opt ~owner ~repo repo_config_table in
  (* Original: hardcoded labels "needs: full CI", "needs: rebase", "stale"
     Now: use repo_config.labels if available, fallback to hardcoded values *)
  let needs_full_ci_label =
    match repo_config with
    | Some config -> (
      match config.labels with
      | Some labels ->
          Option.value ~default:"needs: full CI" labels.needs_full_ci
      | None ->
          "needs: full CI" )
    | None ->
        "needs: full CI"
  in
  let rebase_label =
    match repo_config with
    | Some config -> (
      match config.labels with
      | Some labels ->
          Option.value ~default:"needs: rebase" labels.needs_rebase
      | None ->
          "needs: rebase" )
    | None ->
        "needs: rebase"
  in
  let stale_label =
    match repo_config with
    | Some config -> (
      match config.labels with
      | Some labels ->
          Option.value ~default:"stale" labels.stale
      | None ->
          "stale" )
    | None ->
        "stale"
  in
  let open Lwt_result.Syntax in
  if ok then (
    (* Remove rebase / stale label *)
    GitHub_automation.remove_labels_if_present ~bot_info pr_info.issue
      [rebase_label; stale_label] ;
    (* Refactored to remove hardcoded repository checks

       Before: Had hardcoded check for "rocq-prover"/"rocq" to enable CI protection.
       Now: Only checks if repo has config with org_name and team_name configured.

       This prevents untrusted contributors from circumventing manual jobs by
       changing the CI configuration. *)
    let open Lwt.Infix in
    (* Check if repo has config (feature enabled) *)
    let* can_trigger_ci =
      if has_repo_config ~owner ~repo repo_config_table && not skip_author_check
      then
        git_test_modified ~base:pr_info.base.sha ~head:pr_info.head.sha
          ".*gitlab.*\\.yml"
        >>= function
        | Ok config_modified when config_modified -> (
          (* Check team membership to prevent CI file modification by untrusted contributors *)
          match repo_config with
          | Some c -> (
            match (c.org_name, c.team_name) with
            | Some org, Some team -> (
                GitHub_queries.get_team_membership ~bot_info ~org ~team
                  ~user:pr_info.issue.user
                >>= fun is_member_result ->
                match is_member_result with
                | Ok true ->
                    Lwt.return_ok true (* Is member, can trigger CI *)
                | Ok false | Error _ ->
                    Lwt.return_ok
                      false (* Not member or error, cannot trigger CI *) )
            | _ ->
                (* No org/team configured, allow CI changes (can't check membership) *)
                Lwt.return_ok true )
          | None ->
              (* No config, allow CI changes (can't check membership) *)
              Lwt.return_ok true )
        | Ok _ | Error _ ->
            Lwt.return_ok true
      else Lwt.return_ok true
    in
    if not can_trigger_ci then (
      (* Since we cannot trigger CI, in particular, we still need to run a full CI *)
      GitHub_automation.add_labels_if_absent ~bot_info pr_info.issue
        [needs_full_ci_label] ;
      GitHub_mutations.post_comment ~bot_info ~id:pr_info.issue.id
        ~message:
          "I am not triggering a CI run on this PR because the CI \
           configuration has been modified. CI can be triggered manually by an \
           authorized contributor."
      >>= Utils.report_on_posting_comment
      >>= fun () -> Lwt.return_ok () )
    else
      (* BEFORE: Had hardcoded check for "rocq-prover"/"rocq" to enable CI options *)
      (* NOW: Only checks if repo has config (feature enabled) *)
      (* Special CI handling:
         1. if something has changed in docker path, we rebuild the Docker image
         2. if there was a special label set, we run a full CI
      *)
      let get_options =
        if has_repo_config ~owner ~repo repo_config_table then
          (* BEFORE: Used hardcoded docker path pattern and CI variable names *)
          (* NOW: Use repo_config.ci_config if available, fallback to defaults *)
          let docker_path_pattern =
            match repo_config with
            | Some config -> (
              match config.ci_config with
              | Some ci_config ->
                  Option.value ~default:"dev/ci/docker/.*Dockerfile.*"
                    ci_config.docker_path_pattern
              | None ->
                  "dev/ci/docker/.*Dockerfile.*" )
            | None ->
                "dev/ci/docker/.*Dockerfile.*"
          in
          let skip_docker_variable =
            match repo_config with
            | Some config -> (
              match config.ci_config with
              | Some ci_config ->
                  Option.value ~default:"SKIP_DOCKER"
                    ci_config.skip_docker_variable
              | None ->
                  "SKIP_DOCKER" )
            | None ->
                "SKIP_DOCKER"
          in
          let full_ci_variable =
            match repo_config with
            | Some config -> (
              match config.ci_config with
              | Some ci_config ->
                  Option.value ~default:"FULL_CI" ci_config.full_ci_variable
              | None ->
                  "FULL_CI" )
            | None ->
                "FULL_CI"
          in
          let request_full_ci_label =
            match repo_config with
            | Some config -> (
              match config.labels with
              | Some labels ->
                  Option.value ~default:"request: full CI"
                    labels.request_full_ci
              | None ->
                  "request: full CI" )
            | None ->
                "request: full CI"
          in
          Lwt.all
            [ ( git_test_modified ~base:pr_info.base.sha ~head:pr_info.head.sha
                  docker_path_pattern
              >>= function
              | Ok true ->
                  Lwt.return
                    (f {|-o ci.variable="%s=false"|} skip_docker_variable)
              | Ok false ->
                  Lwt.return ""
              | Error e ->
                  Lwt_io.printf
                    "Error while checking if something has changed in \
                     dev/ci/docker:\n\
                     %s\n"
                    e
                  >>= fun () -> Lwt.return "" )
            ; ( match full_ci with
              | Some false ->
                  (* Light CI requested *)
                  GitHub_automation.add_labels_if_absent ~bot_info pr_info.issue
                    [needs_full_ci_label] ;
                  Lwt.return
                    (f {| -o ci.variable="%s=false" |} full_ci_variable)
              | Some true ->
                  (* Full CI requested *)
                  GitHub_automation.remove_labels_if_present ~bot_info
                    pr_info.issue
                    [needs_full_ci_label; request_full_ci_label] ;
                  Lwt.return (f {| -o ci.variable="%s=true" |} full_ci_variable)
              | None ->
                  (* Nothing requested with the command,
                     check if the request label is present *)
                  if
                    pr_info.issue.labels
                    |> List.exists ~f:(fun l ->
                           String.equal l request_full_ci_label )
                  then (
                    (* Full CI requested *)
                    GitHub_automation.remove_labels_if_present ~bot_info
                      pr_info.issue
                      [needs_full_ci_label; request_full_ci_label] ;
                    Lwt.return
                      (f {| -o ci.variable="%s=true" |} full_ci_variable) )
                  else (
                    (* Nothing requested *)
                    GitHub_automation.add_labels_if_absent ~bot_info
                      pr_info.issue [needs_full_ci_label] ;
                    Lwt.return
                      (f {| -o ci.variable="%s=false" |} full_ci_variable) ) )
            ]
          >|= fun options -> String.concat ~sep:" " options
        else Lwt.return ""
      in
      (* Force push *)
      get_options
      >>= fun options ->
      let open Lwt_result.Infix in
      gitlab_ci_ref_for_github_pr ~issue:pr_info.issue.issue ~gitlab_mapping
        ~github_mapping ~bot_info
      >>= fun remote_ref ->
      git_push ~force:true ~options ~remote_ref ~local_ref:local_head_branch ()
      |> execute_cmd )
  else (
    (* Add rebase label if it exists *)
    GitHub_automation.add_labels_if_absent ~bot_info pr_info.issue [rebase_label] ;
    (* Add fail status check *)
    match bot_info.github_install_token with
    | None ->
        GitHub_mutations.send_status_check
          ~repo_full_name:
            (f "%s/%s" pr_info.issue.issue.owner pr_info.issue.issue.repo)
          ~commit:pr_info.head.sha ~state:"error" ~url:""
          ~context:"GitLab CI pipeline (pull request)"
          ~description:
            "Pipeline did not run on GitLab CI because PR has conflicts with \
             base branch."
          ~bot_info
        |> Lwt_result.ok
    | Some _ -> (
        let open Lwt.Infix in
        let open Lwt.Syntax in
        GitHub_queries.get_repository_id ~bot_info
          ~owner:pr_info.issue.issue.owner ~repo:pr_info.issue.issue.repo
        >>= function
        | Ok repo_id ->
            (let+ _ =
               GitHub_mutations.create_check_run ~bot_info
                 ~name:"GitLab CI pipeline (pull request)" ~status:COMPLETED
                 ~repo_id ~head_sha:pr_info.head.sha ~conclusion:FAILURE
                 ~title:
                   "Pipeline did not run on GitLab CI because PR has conflicts \
                    with base branch."
                 ~details_url:"" ~summary:"" ()
             in
             () )
            |> Lwt_result.ok
        | Error e ->
            Lwt.return (Error e) ) )

let run_ci_action ~bot_info ~repo_config_table ~comment_info ?full_ci
    ~gitlab_mapping ~github_mapping () =
  let owner = comment_info.issue.issue.owner in
  let repo = comment_info.issue.issue.repo in
  let repo_config = get_repo_config_opt ~owner ~repo repo_config_table in
  (* BEFORE: Had hardcoded org="rocq-prover" and team="contributors" *)
  (* NOW: Use repo_config.org_name and repo_config.team_name (required for feature) *)
  let org, team =
    match repo_config with
    | Some config -> (
      match (config.org_name, config.team_name) with
      | Some org, Some team ->
          (org, team)
      | _ ->
          (* No org/team configured - this shouldn't happen if feature is enabled *)
          failwith
            "run_ci_action called but org_name or team_name not configured" )
    | None ->
        failwith "run_ci_action called but no repo config found"
  in
  (fun () ->
    (let open Lwt_result.Infix in
     GitHub_queries.get_team_membership ~bot_info ~org ~team
       ~user:comment_info.author
     >>= (fun is_member ->
           if is_member then
             let open Lwt.Syntax in
             let* () = Lwt_io.printl "Authorized user: pushing to GitLab." in
             match comment_info.pull_request with
             | Some pr_info ->
                 update_pr ~skip_author_check:true pr_info ~bot_info
                   ~repo_config_table ~gitlab_mapping ~github_mapping
             | None ->
                 let {owner; repo; number} = comment_info.issue.issue in
                 GitHub_queries.get_pull_request_refs ~bot_info ~owner ~repo
                   ~number
                 >>= fun pr_info ->
                 update_pr ?full_ci ~skip_author_check:true
                   {pr_info with issue= comment_info.issue}
                   ~bot_info ~repo_config_table ~gitlab_mapping ~github_mapping
           else
             (* We inform the author of the request that they are not authorized. *)
             GitHub_automation.inform_user_not_in_contributors ~bot_info
               ~comment_info
             |> Lwt_result.ok )
     |> Fn.flip Lwt_result.bind_lwt_error (fun err ->
            Lwt_io.printf "Error: %s\n" err ) )
    >>= fun _ -> Lwt.return_unit )
  |> Lwt.async ;
  Server.respond_string ~status:`OK
    ~body:
      (f
         "Received a request to run CI: checking that @%s is a member of \
          @%s/%s before doing so."
         comment_info.author comment_info.issue.issue.owner team )
    ()

let pull_request_updated_action ~bot_info ~repo_config_table
    ~(action : GitHub_types.pull_request_action)
    ~(pr_info : GitHub_types.issue_info GitHub_types.pull_request_info)
    ~gitlab_mapping ~github_mapping =
  let owner = pr_info.issue.issue.owner in
  let repo = pr_info.issue.issue.repo in
  let repo_url = f "https://github.com/%s/%s" owner repo in
  (* BEFORE: Had hardcoded check for "rocq-prover"/"rocq" *)
  (* NOW: Only checks if repo has config (feature enabled) *)
  ( match (action, pr_info.base.branch.repo_url) with
  | PullRequestOpened, url
    when String.equal url repo_url
         && String.equal pr_info.base.branch.name pr_info.head.branch.name
         && has_repo_config ~owner ~repo repo_config_table ->
      (fun () ->
        GitHub_mutations.post_comment ~bot_info ~id:pr_info.issue.id
          ~message:
            (f
               "Hello, thanks for your pull request!\n\
                In the future, we strongly recommend that you *do not* use %s \
                as the name of your branch when submitting a pull request.\n\
                By the way, you may be interested in reading [our contributing \
                guide](https://github.com/rocq-prover/rocq/blob/master/CONTRIBUTING.md)."
               pr_info.base.branch.name )
        >>= Utils.report_on_posting_comment )
      |> Lwt.async
  | _ ->
      () ) ;
  (fun () ->
    update_pr pr_info ~bot_info ~repo_config_table ~gitlab_mapping
      ~github_mapping
    >>= fun _ -> Lwt.return_unit )
  |> Lwt.async ;
  Server.respond_string ~status:`OK
    ~body:
      (f
         "Pull request %s/%s#%d was (re)opened / synchronized: (force-)pushing \
          to GitLab."
         pr_info.issue.issue.owner pr_info.issue.issue.repo
         pr_info.issue.issue.number )
    ()

let apply_after_label ~bot_info ~owner ~repo ~after ~label ~action ~throttle ()
    =
  GitHub_queries.get_open_pull_requests_with_label ~bot_info ~owner ~repo ~label
  >>= function
  | Ok prs ->
      let iter (pr_id, pr_number) =
        GitHub_queries.get_pull_request_label_timeline ~bot_info ~owner ~repo
          ~pr_number
        >>= function
        | Ok timeline ->
            let find (set, name, ts) =
              if set && String.equal name label then Some ts else None
            in
            (* Look for most recent label setting *)
            let timeline = List.rev timeline in
            let days =
              match List.find_map ~f:find timeline with
              | None ->
                  (* even with a race condition it cannot happen *)
                  failwith
                    (f {|Anomaly: Label "%s" absent from timeline of PR #%i|}
                       label pr_number )
              | Some ts ->
                  Utils.days_elapsed ts
            in
            if days >= after then action pr_id pr_number else Lwt.return false
        | Error e ->
            Lwt_io.print (f "Error: %s\n" e) >>= fun () -> Lwt.return false
      in
      Utils.apply_throttle throttle iter prs
  | Error err ->
      Lwt_io.print (f "Error: %s\n" err)

let rocq_check_needs_rebase_pr ~bot_info ~repo_config_table ~owner ~repo
    ~warn_after ~close_after ~throttle =
  let repo_config = get_repo_config_opt ~owner ~repo repo_config_table in
  (* Original: hardcoded labels "needs: rebase", "stale", "needs: independent fix"
     Now: use repo_config.labels if available, fallback to hardcoded values *)
  let rebase_label =
    match repo_config with
    | Some config -> (
      match config.labels with
      | Some labels ->
          Option.value ~default:"needs: rebase" labels.needs_rebase
      | None ->
          "needs: rebase" )
    | None ->
        "needs: rebase"
  in
  let stale_label =
    match repo_config with
    | Some config -> (
      match config.labels with
      | Some labels ->
          Option.value ~default:"stale" labels.stale
      | None ->
          "stale" )
    | None ->
        "stale"
  in
  let needs_independent_fix_label =
    match repo_config with
    | Some config -> (
      match config.labels with
      | Some labels ->
          Option.value ~default:"needs: independent fix"
            labels.needs_independent_fix
      | None ->
          "needs: independent fix" )
    | None ->
        "needs: independent fix"
  in
  GitHub_queries.get_label ~bot_info ~owner ~repo ~label:stale_label
  >>= function
  | Ok None ->
      Lwt.return_unit
  | Ok (Some stale_id) ->
      let action pr_id pr_number =
        GitHub_queries.get_pull_request_labels ~bot_info ~owner ~repo ~pr_number
        >>= function
        | Ok labels ->
            let has_label l = List.mem labels ~equal:String.equal l in
            if
              not
                (has_label stale_label || has_label needs_independent_fix_label)
            then
              GitHub_mutations.post_comment ~id:pr_id
                ~message:
                  (f
                     "The \"%s\" label was set more than %i days ago. If the \
                      PR is not rebased in %i days, it will be automatically \
                      closed."
                     rebase_label warn_after close_after )
                ~bot_info
              >>= Utils.report_on_posting_comment
              >>= fun () ->
              GitHub_mutations.add_labels ~bot_info ~labels:[stale_id]
                ~issue:pr_id
              >>= fun () -> Lwt.return true
            else Lwt.return false
        | Error err ->
            Lwt_io.print (f "Error: %s\n" err) >>= fun () -> Lwt.return false
      in
      apply_after_label ~bot_info ~owner ~repo ~after:warn_after
        ~label:rebase_label ~action ~throttle ()
  | Error err ->
      Lwt_io.print (f "Error: %s\n" err)

let rocq_check_stale_pr ~bot_info ~repo_config_table ~owner ~repo ~after
    ~throttle =
  let repo_config = get_repo_config_opt ~owner ~repo repo_config_table in
  (* Original: hardcoded label "stale"
     Now: use repo_config.labels if available, fallback to hardcoded value *)
  let label =
    match repo_config with
    | Some config -> (
      match config.labels with
      | Some labels ->
          Option.value ~default:"stale" labels.stale
      | None ->
          "stale" )
    | None ->
        "stale"
  in
  let action pr_id _pr_number =
    GitHub_mutations.post_comment ~id:pr_id
      ~message:
        (f
           "This PR was not rebased after %i days despite the warning, it is \
            now closed."
           after )
      ~bot_info
    >>= Utils.report_on_posting_comment
    >>= fun () ->
    GitHub_mutations.close_pull_request ~bot_info ~pr_id
    >>= fun () -> Lwt.return true
  in
  apply_after_label ~bot_info ~owner ~repo ~after ~label ~action ~throttle ()
