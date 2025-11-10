open Base
open Bot_components
open Bot_components.GitHub_types
open Lwt.Infix
open Lwt.Syntax

let rocq_push_action ~bot_info ~base_ref ~commits_msg =
  let* () = Lwt_io.printl "Merge and backport commit messages:" in
  let commit_action commit_msg =
    if
      String_utils.string_match
        ~regexp:"^Merge \\(PR\\|pull request\\) #\\([0-9]*\\)" commit_msg
    then
      let pr_number = Str.matched_group 2 commit_msg |> Int.of_string in
      Lwt_io.printf "%s\nPR #%d was merged.\n" commit_msg pr_number
      >>= fun () ->
      GitHub_queries.get_pull_request_id_and_milestone ~bot_info
        ~owner:"rocq-prover" ~repo:"rocq" ~number:pr_number
      >>= fun pr_info ->
      match pr_info with
      | Ok (pr_id, backport_info) ->
          backport_info
          |> Lwt_list.iter_p (fun {backport_to} ->
                 if "refs/heads/" ^ backport_to |> String.equal base_ref then
                   Lwt_io.printf
                     "PR was merged into the backporting branch directly.\n"
                   >>= fun () ->
                   GitHub_automation.add_to_column ~bot_info ~backport_to
                     (`PR_ID pr_id) "Shipped"
                 else if String.equal base_ref "refs/heads/master" then
                   (* For now, we hard code that PRs are only backported
                      from master.  In the future, we could make this
                      configurable in the milestone description or in
                      some configuration file. *)
                   Lwt_io.printf "Backporting to %s was requested.\n"
                     backport_to
                   >>= fun () ->
                   GitHub_automation.add_to_column ~bot_info ~backport_to
                     (`PR_ID pr_id) "Request inclusion"
                 else
                   Lwt_io.printf
                     "PR was merged into a branch that is not the backporting \
                      branch nor the master branch.\n" )
      | Error err ->
          Lwt_io.printf "Error: %s\n" err
    else if
      String_utils.string_match ~regexp:"^Backport PR #\\([0-9]*\\):" commit_msg
    then
      let pr_number = Str.matched_group 1 commit_msg |> Int.of_string in
      Lwt_io.printf "%s\nPR #%d was backported.\n" commit_msg pr_number
      >>= fun () ->
      GitHub_queries.get_pull_request_cards ~bot_info ~owner:"rocq-prover"
        ~repo:"rocq" ~number:pr_number
      >>= function
      | Ok items -> (
          let backport_to =
            String.chop_prefix_if_exists ~prefix:"refs/heads/" base_ref
          in
          let card_id =
            items |> List.find_map ~f:(function id, 11 -> Some id | _ -> None)
          in
          match card_id with
          | Some card_id ->
              Lwt_io.printlf
                "Pull request rocq-prover/rocq#%d found in project 11. \
                 Updating its fields."
                pr_number
              >>= fun () ->
              GitHub_automation.add_to_column ~bot_info ~backport_to
                (`Card_ID card_id) "Shipped"
          | None ->
              (* We could do something in this case, like post a comment to
                 the PR and add the PR to the project. *)
              Lwt_io.printlf
                "Pull request rocq-prover/rocq#%d not found in project 11."
                pr_number )
      | Error e ->
          Lwt_io.printf "%s\n" e
    else Lwt.return_unit
  in
  Lwt_list.iter_s commit_action commits_msg
