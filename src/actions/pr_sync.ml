open Base
open Bot_components
open Bot_components.GitHub_types
open Bot_components.GitHub_GitLab_sync
open Cohttp_lwt_unix
open Git_utils
open Utils
open Lwt.Infix

(* TODO: ensure there's no race condition for 2 push with very close timestamps *)
let update_pr ?full_ci ?(skip_author_check = false) ~bot_info
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
  let needs_full_ci_label = "needs: full CI" in
  let rebase_label = "needs: rebase" in
  let stale_label = "stale" in
  let open Lwt_result.Syntax in
  if ok then (
    (* Remove rebase / stale label *)
    GitHub_automation.remove_labels_if_present ~bot_info pr_info.issue
      [rebase_label; stale_label] ;
    (* In the Rocq Prover repo, we want to prevent untrusted contributors from
       circumventing the fact that the bench job is a manual job by changing
       the CI configuration. *)
    let* can_trigger_ci =
      if
        String.equal pr_info.issue.issue.owner "rocq-prover"
        && String.equal pr_info.issue.issue.repo "rocq"
        && not skip_author_check
      then
        let* config_modified =
          git_test_modified ~base:pr_info.base.sha ~head:pr_info.head.sha
            ".*gitlab.*\\.yml"
        in
        if config_modified then (
          Lwt.async (fun () ->
              Lwt_io.printlf
                "CI configuration modified in PR rocq-prover/rocq#%d, checking \
                 if %s is a member of @rocq-prover/contributors..."
                pr_info.issue.number pr_info.issue.user ) ;
          (* This is an approximation:
             we are checking who the PR author is and not who is pushing. *)
          GitHub_queries.get_team_membership ~bot_info ~org:"rocq-prover"
            ~team:"contributors" ~user:pr_info.issue.user )
        else Lwt.return_ok true
      else Lwt.return_ok true
    in
    let open Lwt.Infix in
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
      (* In Rocq Prover repo, we have several special cases:
         1. if something has changed in dev/ci/docker/, we rebuild the Docker image
         2. if there was a special label set, we run a full CI
      *)
      let get_options =
        if
          String.equal pr_info.issue.issue.owner "rocq-prover"
          && String.equal pr_info.issue.issue.repo "rocq"
        then
          Lwt.all
            [ ( git_test_modified ~base:pr_info.base.sha ~head:pr_info.head.sha
                  "dev/ci/docker/.*Dockerfile.*"
              >>= function
              | Ok true ->
                  Lwt.return {|-o ci.variable="SKIP_DOCKER=false"|}
              | Ok false ->
                  Lwt.return ""
              | Error e ->
                  Lwt_io.printf
                    "Error while checking if something has changed in \
                     dev/ci/docker:\n\
                     %s\n"
                    e
                  >>= fun () -> Lwt.return "" )
            ; (let request_full_ci_label = "request: full CI" in
               match full_ci with
               | Some false ->
                   (* Light CI requested *)
                   GitHub_automation.add_labels_if_absent ~bot_info
                     pr_info.issue [needs_full_ci_label] ;
                   Lwt.return {| -o ci.variable="FULL_CI=false" |}
               | Some true ->
                   (* Full CI requested *)
                   GitHub_automation.remove_labels_if_present ~bot_info
                     pr_info.issue
                     [needs_full_ci_label; request_full_ci_label] ;
                   Lwt.return {| -o ci.variable="FULL_CI=true" |}
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
                     Lwt.return {| -o ci.variable="FULL_CI=true" |} )
                   else (
                     (* Nothing requested *)
                     GitHub_automation.add_labels_if_absent ~bot_info
                       pr_info.issue [needs_full_ci_label] ;
                     Lwt.return {| -o ci.variable="FULL_CI=false" |} ) ) ]
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
    let open Lwt.Infix in
    let open Lwt.Syntax in
    GitHub_queries.get_repository_id ~bot_info ~owner:pr_info.issue.issue.owner
      ~repo:pr_info.issue.issue.repo
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
        Lwt.return (Error e) )

let run_ci_action ~bot_info ~comment_info ?full_ci ~gitlab_mapping
    ~github_mapping () =
  let team = "contributors" in
  (fun () ->
    (let open Lwt_result.Infix in
     GitHub_queries.get_team_membership ~bot_info ~org:"rocq-prover" ~team
       ~user:comment_info.author
     >>= (fun is_member ->
           if is_member then
             let open Lwt.Syntax in
             let* () = Lwt_io.printl "Authorized user: pushing to GitLab." in
             match comment_info.pull_request with
             | Some pr_info ->
                 update_pr ~skip_author_check:true pr_info ~bot_info
                   ~gitlab_mapping ~github_mapping
             | None ->
                 let {owner; repo; number} = comment_info.issue.issue in
                 GitHub_queries.get_pull_request_refs ~bot_info ~owner ~repo
                   ~number
                 >>= fun pr_info ->
                 update_pr ?full_ci ~skip_author_check:true
                   {pr_info with issue= comment_info.issue}
                   ~bot_info ~gitlab_mapping ~github_mapping
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

let pull_request_updated_action ~bot_info
    ~(action : GitHub_types.pull_request_action)
    ~(pr_info : GitHub_types.issue_info GitHub_types.pull_request_info)
    ~gitlab_mapping ~github_mapping =
  ( match (action, pr_info.base.branch.repo_url) with
  | PullRequestOpened, "https://github.com/rocq-prover/rocq"
    when String.equal pr_info.base.branch.name pr_info.head.branch.name ->
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
    update_pr pr_info ~bot_info ~gitlab_mapping ~github_mapping
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

let rocq_check_needs_rebase_pr ~bot_info ~owner ~repo ~warn_after ~close_after
    ~throttle =
  let rebase_label = "needs: rebase" in
  let stale_label = "stale" in
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
            if not (has_label stale_label || has_label "needs: independent fix")
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

let rocq_check_stale_pr ~bot_info ~owner ~repo ~after ~throttle =
  let label = "stale" in
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
