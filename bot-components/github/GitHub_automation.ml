open Base
open GitHub_types
open Utils
open Lwt.Infix
open Git_utils
open GitHub_GitLab_sync

let rec merge_pull_request_action ~bot_info ?(t = 1.) comment_info =
  let pr = comment_info.issue in
  let reasons_for_not_merging =
    List.filter_opt
      [ ( if String.equal comment_info.author pr.user then
            Some "You are the author."
          else if
            List.exists
              ~f:(String.equal comment_info.author)
              comment_info.issue.assignees
          then None
          else Some "You are not among the assignees." )
      ; comment_info.issue.labels
        |> List.find ~f:(fun label ->
            String_utils.string_match ~regexp:"needs:.*" label )
        |> Option.map ~f:(fun l -> f "There is still a `%s` label." l)
      ; ( if
            comment_info.issue.labels
            |> List.exists ~f:(fun label ->
                String_utils.string_match ~regexp:"kind:.*" label )
          then None
          else Some "There is no `kind:` label." )
      ; ( if comment_info.issue.milestoned then None
          else Some "No milestone has been set." ) ]
  in
  ( match reasons_for_not_merging with
    | _ :: _ ->
        let bullet_reasons =
          reasons_for_not_merging |> List.map ~f:(fun x -> "- " ^ x)
        in
        let reasons = bullet_reasons |> String.concat ~sep:"\n" in
        Lwt.return_error
          (f "@%s: You cannot merge this PR because:\n%s" comment_info.author
             reasons )
    | [] -> (
        GitHub_queries.get_pull_request_reviews_refs ~bot_info
          ~owner:pr.issue.owner ~repo:pr.issue.repo ~number:pr.issue.number
        >>= function
        | Ok reviews_info -> (
            let comment =
              List.find reviews_info.last_comments ~f:(fun c ->
                  GitHub_ID.equal comment_info.id c.id )
            in
            if (not comment_info.review_comment) && Option.is_none comment then
              if Float.(t > 5.) then
                Lwt.return_error
                  "Something unexpected happened: did not find merge comment \
                   after retrying three times.\n\
                   cc @rocq-prover/coqbot-maintainers"
              else
                Lwt_unix.sleep t
                >>= fun () ->
                merge_pull_request_action ~t:(t *. 2.) ~bot_info comment_info
                >>= fun () -> Lwt.return_ok ()
            else if
              (not comment_info.review_comment)
              && (Option.value_exn comment).created_by_email
              (* Option.value_exn doesn't raise an exception because comment isn't None at this point*)
            then
              Lwt.return_error
                (f
                   "@%s: Merge requests sent over e-mail are not accepted \
                    because this puts less guarantee on the authenticity of \
                    the author of the request."
                   comment_info.author )
            else if not (String.equal reviews_info.baseRef "master") then
              Lwt.return_error
                (f
                   "@%s: This PR targets branch `%s` instead of `master`. Only \
                    release managers can merge in release branches. If you are \
                    the release manager for this branch, you should use the \
                    `dev/tools/merge-pr.sh` script to merge this PR. Merging \
                    with the bot is not supported yet."
                   comment_info.author reviews_info.baseRef )
            else
              match reviews_info.review_decision with
              | NONE | REVIEW_REQUIRED ->
                  Lwt.return_error
                    (f
                       "@%s: You can't merge the PR because it hasn't been \
                        approved yet."
                       comment_info.author )
              | CHANGES_REQUESTED ->
                  Lwt.return_error
                    (f
                       "@%s: You can't merge the PR because some changes are \
                        requested."
                       comment_info.author )
              | APPROVED -> (
                  GitHub_queries.get_team_membership ~bot_info
                    ~org:"rocq-prover" ~team:"pushers" ~user:comment_info.author
                  >>= function
                  | Ok false ->
                      (* User not found in the team *)
                      Lwt.return_error
                        (f
                           "@%s: You can't merge this PR because you're not a \
                            member of the `@rocq-prover/pushers` team. Look at \
                            the contributing guide for how to join this team."
                           comment_info.author )
                  | Ok true -> (
                      GitHub_mutations.merge_pull_request ~bot_info ~pr_id:pr.id
                        ~commit_headline:
                          (f "Merge PR #%d: %s" pr.issue.number
                             comment_info.issue.title )
                        ~commit_body:
                          ( List.fold_left reviews_info.approved_reviews ~init:""
                              ~f:(fun s r -> s ^ f "Reviewed-by: %s\n" r )
                          ^ List.fold_left reviews_info.comment_reviews ~init:""
                              ~f:(fun s r -> s ^ f "Ack-by: %s\n" r )
                          ^ f
                              "Co-authored-by: %s <%s@users.noreply.github.com>\n"
                              comment_info.author comment_info.author )
                        ~merge_method:MERGE ()
                      >>= fun () ->
                      match
                        List.fold_left ~init:[] reviews_info.files
                          ~f:(fun acc f ->
                            if
                              String_utils.string_match
                                ~regexp:"dev/ci/user-overlays/\\(.*\\)" f
                            then
                              let f = Str.matched_group 1 f in
                              if String.equal f "README.md" then acc
                              else f :: acc
                            else acc )
                      with
                      | [] ->
                          Lwt.return_ok ()
                      | overlays ->
                          GitHub_mutations.post_comment ~bot_info ~id:pr.id
                            ~message:
                              (f
                                 "@%s: Please take care of the following \
                                  overlays:\n\
                                  %s"
                                 comment_info.author
                                 (List.fold_left overlays ~init:""
                                    ~f:(fun s o -> s ^ f "- %s\n" o ) ) )
                          >>= Utils.report_on_posting_comment
                          >>= fun () -> Lwt.return_ok () )
                  | Error e ->
                      Lwt.return_error
                        (f
                           "Something unexpected happened: %s\n\
                            cc @rocq-prover/coqbot-maintainers"
                           e ) ) )
        | Error e ->
            Lwt.return_error
              (f
                 "Something unexpected happened: %s\n\
                  cc @rocq-prover/coqbot-maintainers"
                 e ) ) )
  >>= function
  | Ok () ->
      Lwt.return_unit
  | Error err ->
      GitHub_mutations.post_comment ~bot_info ~message:err ~id:pr.id
      >>= Utils.report_on_posting_comment

let reflect_pull_request_milestone ~bot_info pr_closer_info =
  match pr_closer_info.closer.milestone_id with
  | None ->
      Lwt_io.printf "PR closed without a milestone: doing nothing.\n"
  | Some milestone -> (
    match pr_closer_info.milestone_id with
    | None ->
        (* No previous milestone: setting the one of the PR which closed the issue *)
        GitHub_mutations.update_milestone_issue ~bot_info
          ~issue:pr_closer_info.issue_id ~milestone
    | Some previous_milestone when GitHub_ID.equal previous_milestone milestone
      ->
        Lwt_io.print "Issue is already in the right milestone: doing nothing.\n"
    | Some _ ->
        GitHub_mutations.update_milestone_issue ~bot_info
          ~issue:pr_closer_info.issue_id ~milestone
        <&> ( GitHub_mutations.post_comment ~bot_info ~id:pr_closer_info.issue_id
                ~message:
                  "The milestone of this issue was changed to reflect the one \
                   of the pull request that closed it."
            >>= Utils.report_on_posting_comment ) )

let rec adjust_milestone ~bot_info ~issue ~sleep_time =
  (* We implement an exponential backoff strategy to try again after
     5, 25, and 125 seconds, if the issue was closed by a commit not
     yet associated to a pull request or if we couldn't find the close
     event. *)
  GitHub_queries.get_issue_closer_info ~bot_info issue
  >>= function
  | Ok (ClosedByPullRequest result) ->
      reflect_pull_request_milestone ~bot_info result
  | Ok ClosedByCommit when Float.(sleep_time > 200.) ->
      Lwt_io.print "Closed by commit not associated to any pull request.\n"
  | Ok NoCloseEvent when Float.(sleep_time > 200.) ->
      Lwt_io.printf "Error: no close event after 200 seconds.\n"
  | Ok (ClosedByCommit | NoCloseEvent) ->
      (* May be worth trying again later. *)
      Lwt_io.printf
        "Closed by commit not yet associated to any pull request or no close \
         event yet...\n\
        \ Trying again in %f seconds.\n"
        sleep_time
      >>= (fun () -> Lwt_unix.sleep sleep_time)
      >>= fun () ->
      adjust_milestone ~issue ~sleep_time:(sleep_time *. 5.) ~bot_info
  | Ok ClosedByOther ->
      (* Not worth trying again *)
      Lwt_io.print "Not closed by pull request or commit.\n"
  | Error err ->
      Lwt_io.print (f "Error: %s\n" err)

let add_to_column ~bot_info ~organization ~project ~backport_to id option =
  let field = backport_to ^ " status" in
  GitHub_queries.get_project_field_values ~bot_info ~organization ~project
    ~field ~options:[|option|]
  >>= fun project_info ->
  ( match project_info with
    | Ok (project_id, Some (field_id, [(option', field_value_id)]))
      when String.equal option option' ->
        Lwt.return_ok (project_id, field_id, field_value_id)
    | Ok (_, Some (_, [])) ->
        Lwt.return_error
          (f "Error: Could not find '%s' option in the field." option)
    | Ok (_, Some _) ->
        Lwt.return_error
          (f "Error: Unexpected result when looking for '%s'." option)
    | Ok (project_id, None) -> (
        Lwt_io.printlf
          "Required backporting field '%s' does not exist yet. Creating it..."
          field
        >>= fun () ->
        GitHub_mutations.create_new_release_management_field ~bot_info
          ~project_id ~field
        >>= function
        | Ok (field_id, options) -> (
          match
            List.find_map options ~f:(fun (option', field_value_id) ->
                if String.equal option option' then Some field_value_id
                else None )
          with
          | Some field_value_id ->
              Lwt.return_ok (project_id, field_id, field_value_id)
          | None ->
              Lwt.return_error
                (f
                   "Error new field '%s status' was created, but does not have \
                    a '%s' option."
                   field option ) )
        | Error err ->
            Lwt.return_error
              (f "Error while creating new backporting field '%s': %s" field err)
        )
    | Error err ->
        Lwt.return_error (f "Error while getting project field values: %s" err)
    )
  >>= function
  | Ok (project_id, field_id, field_value_id) -> (
      ( match id with
        | `PR_ID card_id ->
            GitHub_mutations.add_card_to_project ~bot_info ~card_id ~project_id
        | `Card_ID card_id ->
            Lwt.return_ok card_id )
      >>= fun result ->
      match result with
      | Ok card_id ->
          GitHub_mutations.update_field_value ~bot_info ~card_id ~project_id
            ~field_id ~field_value_id
      | Error err ->
          Lwt_io.printf "Error while adding card to project: %s\n" err )
  | Error err ->
      Lwt_io.printl err

let pull_request_closed_action ~bot_info
    (pr_info : issue_info pull_request_info) ~gitlab_mapping ~github_mapping
    ~remove_milestone_if_not_merged =
  let open Lwt.Infix in
  gitlab_ci_ref_for_github_pr ~bot_info ~issue:pr_info.issue.issue
    ~github_mapping ~gitlab_mapping
  >>= (function
  | Ok remote_ref ->
      git_delete ~remote_ref |> execute_cmd >|= ignore
  | Error err ->
      Lwt_io.printlf "Error: %s" err )
  <&>
  if remove_milestone_if_not_merged && not pr_info.merged then
    Lwt_io.printf
      "PR was closed without getting merged: remove the milestone.\n"
    >>= fun () ->
    GitHub_mutations.remove_milestone pr_info.issue.issue ~bot_info
  else
    (* TODO: if PR was merged in master without a milestone, post an alert *)
    Lwt.return_unit

let add_remove_labels ~bot_info ~add (issue : issue_info) labels =
  let open Lwt.Syntax in
  let* labels =
    let open Lwt.Infix in
    labels
    |> Lwt_list.filter_map_p (fun label ->
        GitHub_queries.get_label ~bot_info ~owner:issue.issue.owner
          ~repo:issue.issue.repo ~label
        >|= function
        | Ok (Some label) ->
            Some label
        | Ok None ->
            (* Warn when a label is not found *)
            (fun () ->
              Lwt_io.printlf "Warning: Label %s not found in repository %s/%s."
                label issue.issue.owner issue.issue.repo )
            |> Lwt.async ;
            None
        | Error err ->
            (* Print any other error, but do not prevent acting on other labels *)
            (fun () ->
              Lwt_io.printlf
                "Error while querying for label %s in repository %s/%s: %s"
                label issue.issue.owner issue.issue.repo err )
            |> Lwt.async ;
            None )
  in
  match labels with
  | [] ->
      (* Nothing to do *)
      Lwt.return_unit
  | _ ->
      if add then GitHub_mutations.add_labels ~bot_info ~issue:issue.id ~labels
      else GitHub_mutations.remove_labels ~bot_info ~issue:issue.id ~labels

let add_labels_if_absent ~bot_info (issue : issue_info) labels =
  (* We construct the list of labels to add by filtering out the labels that
     are already present. *)
  (fun () ->
    List.filter labels ~f:(fun label ->
        not (List.mem issue.labels label ~equal:String.equal) )
    |> add_remove_labels ~bot_info ~add:true issue )
  |> Lwt.async

let remove_labels_if_present ~bot_info (issue : issue_info) labels =
  (* We construct the list of labels to remove by keeping only the labels that
     are present. *)
  (fun () ->
    List.filter labels ~f:(fun label ->
        List.mem issue.labels label ~equal:String.equal )
    |> add_remove_labels ~bot_info ~add:false issue )
  |> Lwt.async

let inform_user_not_in_contributors ~bot_info ~comment_info =
  GitHub_mutations.post_comment ~bot_info ~id:comment_info.issue.id
    ~message:
      (f
         "Sorry, @%s, I only accept requests from members of the \
          `@rocq-prover/contributors` team. If you are a regular contributor, \
          you can request to join the team by asking any core developer."
         comment_info.author )
  >>= Utils.report_on_posting_comment
