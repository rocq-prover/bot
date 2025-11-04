open Base
open GitHub_types
open Cohttp_lwt_unix
open Lwt
open Utils

let send_graphql_query = GraphQL_query.send_graphql_query ~api:GitHub

let conclusion_to_graphql = function
  | ACTION_REQUIRED ->
      `ACTION_REQUIRED
  | CANCELLED ->
      `CANCELLED
  | FAILURE ->
      `FAILURE
  | NEUTRAL ->
      `NEUTRAL
  | SKIPPED ->
      `SKIPPED
  | STALE ->
      `STALE
  | SUCCESS ->
      `SUCCESS
  | TIMED_OUT ->
      `TIMED_OUT

let add_card_to_project ~bot_info ~card_id ~project_id =
  let open GitHub_GraphQL.AddCardToProject in
  makeVariables
    ~card_id:(GitHub_ID.to_string card_id)
    ~project_id:(GitHub_ID.to_string project_id)
    ()
  |> serializeVariables |> variablesToJson
  |> send_graphql_query ~bot_info ~query
       ~parse:(Fn.compose parse unsafe_fromJson)
  >>= function
  | Ok result -> (
    match result.addProjectV2ItemById with
    | None ->
        Lwt.return_error "No item ID returned."
    | Some {item} -> (
      match item with
      | None ->
          Lwt.return_error "No item ID returned."
      | Some item ->
          Lwt.return_ok (GitHub_ID.of_string item.id) ) )
  | Error err ->
      Lwt.return (Error ("Error while adding card to project: " ^ err))

let update_field_value ~bot_info ~card_id ~project_id ~field_id ~field_value_id
    =
  let open GitHub_GraphQL.UpdateFieldValue in
  makeVariables
    ~card_id:(GitHub_ID.to_string card_id)
    ~project_id:(GitHub_ID.to_string project_id)
    ~field_id:(GitHub_ID.to_string field_id)
    ~field_value_id ()
  |> serializeVariables |> variablesToJson
  |> send_graphql_query ~bot_info ~query
       ~parse:(Fn.compose parse unsafe_fromJson)
  >>= function
  | Ok _ ->
      Lwt.return_unit
  | Error err ->
      Lwt_io.printlf "Error while updating field value: %s" err

let create_new_release_management_field ~bot_info ~project_id ~field =
  let open GitHub_GraphQL.CreateNewReleaseManagementField in
  makeVariables ~project_id:(GitHub_ID.to_string project_id) ~field ()
  |> serializeVariables |> variablesToJson
  |> send_graphql_query ~bot_info ~query
       ~parse:(Fn.compose parse unsafe_fromJson)
  >>= function
  | Ok result -> (
    match result.createProjectV2Field with
    | None ->
        Lwt.return_error "No field returned after creation."
    | Some result -> (
      match result.projectV2Field with
      | None ->
          Lwt.return_error "No field returned after creation."
      | Some (`ProjectV2SingleSelectField result) ->
          Lwt.return_ok
            ( GitHub_ID.of_string result.id
            , result.options |> Array.to_list
              |> List.map ~f:(fun {name; id} -> (name, id)) )
      | Some _ ->
          Lwt.return_error
            "Field returned after creation is not of type single select." ) )
  | Error err ->
      Lwt.return_error (f "Error while creating new field: %s" err)

let post_comment ~bot_info ~id ~message =
  let open GitHub_GraphQL.PostComment in
  makeVariables ~id:(GitHub_ID.to_string id) ~message ()
  |> serializeVariables |> variablesToJson
  |> send_graphql_query ~bot_info ~query
       ~parse:(Fn.compose parse unsafe_fromJson)
  >|= Result.bind ~f:(function
        | {payload= Some {commentEdge= Some {node= Some {url}}}} ->
            Ok url
        | _ ->
            Error "Error while retrieving URL of posted comment." )

let update_milestone_issue ~bot_info ~issue ~milestone =
  let open GitHub_GraphQL.UpdateMilestoneIssue in
  makeVariables
    ~issue:(GitHub_ID.to_string issue)
    ~milestone:(GitHub_ID.to_string milestone)
    ()
  |> serializeVariables |> variablesToJson
  |> send_graphql_query ~bot_info ~query
       ~parse:(Fn.compose parse unsafe_fromJson)
  >>= function
  | Ok _ ->
      Lwt.return_unit
  | Error err ->
      Lwt_io.printlf "Error while updating milestone: %s" err

let update_milestone_pull_request ~bot_info ~pr_id ~milestone =
  let open GitHub_GraphQL.UpdateMilestonePullRequest in
  makeVariables
    ~pr_id:(GitHub_ID.to_string pr_id)
    ~milestone:(GitHub_ID.to_string milestone)
    ()
  |> serializeVariables |> variablesToJson
  |> send_graphql_query ~bot_info ~query
       ~parse:(Fn.compose parse unsafe_fromJson)
  >>= function
  | Ok _ ->
      Lwt.return_unit
  | Error err ->
      Lwt_io.printlf "Error while updating milestone: %s" err

let close_pull_request ~bot_info ~pr_id =
  let open GitHub_GraphQL.ClosePullRequest in
  makeVariables ~pr_id:(GitHub_ID.to_string pr_id) ()
  |> serializeVariables |> variablesToJson
  |> send_graphql_query ~bot_info ~query
       ~parse:(Fn.compose parse unsafe_fromJson)
  >>= function
  | Ok _ ->
      Lwt.return_unit
  | Error err ->
      Lwt_io.printlf "Error while closing PR: %s" err

let merge_pull_request ~bot_info ?merge_method ?commit_headline ?commit_body
    ~pr_id () =
  let merge_method =
    Option.map merge_method ~f:(function
      | MERGE ->
          `MERGE
      | REBASE ->
          `REBASE
      | SQUASH ->
          `SQUASH )
  in
  let open GitHub_GraphQL.MergePullRequest in
  makeVariables
    ~pr_id:(GitHub_ID.to_string pr_id)
    ?commit_headline ?commit_body ?merge_method ()
  |> serializeVariables |> variablesToJson
  |> send_graphql_query ~bot_info ~query
       ~parse:(Fn.compose parse unsafe_fromJson)
  >>= function
  | Ok _ ->
      Lwt.return_unit
  | Error err ->
      Lwt_io.printlf "Error while merging PR: %s" err

let create_check_run ~bot_info ?conclusion ~name ~repo_id ~head_sha ~status
    ~details_url ~title ?text ~summary ?external_id () =
  let conclusion = Option.map conclusion ~f:conclusion_to_graphql in
  let status =
    match status with
    | COMPLETED ->
        `COMPLETED
    | IN_PROGRESS ->
        `IN_PROGRESS
    | QUEUED ->
        `QUEUED
  in
  let open GitHub_GraphQL.NewCheckRun in
  (* Workaround for issue #203 while waiting for resolution of teamwalnut/graphql-ppx#272 *)
  let query =
    "mutation newCheckRun($name: String!, $repoId: ID!, $headSha: \
     GitObjectID!, $status: RequestableCheckStatusState!, $title: String!, \
     $text: String, $summary: String!, $url: URI!, $conclusion: \
     CheckConclusionState, $externalId: String) {\n\
     createCheckRun(input: {status: $status, name: $name, repositoryId: \
     $repoId, headSha: $headSha, conclusion: $conclusion, detailsUrl: $url, \
     output: {title: $title, text: $text, summary: $summary}, externalId: \
     $externalId}) {\n\
     clientMutationId \n\
     }\n\n\
     }\n"
  in
  let open Lwt_result.Infix in
  makeVariables ~name
    ~repoId:(GitHub_ID.to_string repo_id)
    ~headSha:head_sha ~status ~title ?text ~summary ~url:details_url ?conclusion
    ?externalId:external_id ()
  |> serializeVariables |> variablesToJson
  |> send_graphql_query ~bot_info ~query
       ~parse:(Fn.compose parse unsafe_fromJson)
  >>= function
  | {createCheckRun= Some {checkRun= Some {url}}} ->
      Lwt_result.return url
  | _ ->
      Lwt_result.fail (f "No new check run URL provided in GitHub answer.")

let update_check_run ~bot_info ~check_run_id ~repo_id ~conclusion ?details_url
    ~title ?text ~summary () =
  let conclusion = conclusion_to_graphql conclusion in
  let open GitHub_GraphQL.UpdateCheckRun in
  makeVariables
    ~checkRunId:(GitHub_ID.to_string check_run_id)
    ~repoId:(GitHub_ID.to_string repo_id)
    ~conclusion ?url:details_url ~title ?text ~summary ()
  |> serializeVariables |> variablesToJson
  |> send_graphql_query ~bot_info ~query
       ~parse:(Fn.compose parse unsafe_fromJson)
  >>= function
  | Ok _ ->
      Lwt.return_unit
  | Error err ->
      Lwt_io.printlf "Error while updating check run: %s" err

let add_labels ~bot_info ~labels ~issue =
  let open GitHub_GraphQL.LabelIssue in
  makeVariables
    ~issue_id:(GitHub_ID.to_string issue)
    ~label_ids:(List.map ~f:GitHub_ID.to_string labels |> Array.of_list)
    ()
  |> serializeVariables |> variablesToJson
  |> send_graphql_query ~bot_info ~query
       ~parse:(Fn.compose parse unsafe_fromJson)
  >>= fun _ -> Lwt.return_unit

let remove_labels ~bot_info ~labels ~issue =
  let open GitHub_GraphQL.UnlabelIssue in
  makeVariables
    ~issue_id:(GitHub_ID.to_string issue)
    ~label_ids:(List.map ~f:GitHub_ID.to_string labels |> Array.of_list)
    ()
  |> serializeVariables |> variablesToJson
  |> send_graphql_query ~bot_info ~query
       ~parse:(Fn.compose parse unsafe_fromJson)
  >>= fun _ -> Lwt.return_unit

(* TODO: use GraphQL API *)

let remove_milestone ~bot_info (issue : issue) =
  let headers =
    HTTP_utils.headers (HTTP_utils.github_header bot_info) bot_info.github_name
  in
  let uri =
    f "https://api.github.com/repos/%s/%s/issues/%d" issue.owner issue.repo
      issue.number
    |> Uri.of_string
  in
  let body = {|{"milestone": null}|} |> Cohttp_lwt.Body.of_string in
  Lwt_io.printf "Sending patch request.\n"
  >>= fun () -> Client.patch ~headers ~body uri >>= HTTP_utils.print_response

let send_status_check ~bot_info ~repo_full_name ~commit ~state ~url ~context
    ~description =
  Lwt_io.printf "Sending status check to %s (commit %s, state %s)\n"
    repo_full_name commit state
  >>= fun () ->
  let body =
    {|{"state": "|} ^ state ^ {|","target_url":"|} ^ url
    ^ {|", "description": "|} ^ description ^ {|", "context": "|} ^ context
    ^ {|"}|}
    |> Cohttp_lwt.Body.of_string
  in
  let uri =
    "https://api.github.com/repos/" ^ repo_full_name ^ "/statuses/" ^ commit
    |> Uri.of_string
  in
  HTTP_utils.send_request ~body ~uri
    (HTTP_utils.github_header bot_info)
    bot_info.github_name

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
                 Lwt_io.printlf
                   "Warning: Label %s not found in repository %s/%s." label
                   issue.issue.owner issue.issue.repo )
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
      if add then add_labels ~bot_info ~issue:issue.id ~labels
      else remove_labels ~bot_info ~issue:issue.id ~labels

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
  post_comment ~bot_info ~id:comment_info.issue.id
    ~message:
      (f
         "Sorry, @%s, I only accept requests from members of the \
          `@rocq-prover/contributors` team. If you are a regular contributor, \
          you can request to join the team by asking any core developer."
         comment_info.author )
  >>= report_on_posting_comment
