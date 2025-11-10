open Base
open Bot_components
open GitLab_types
open GitHub_types
open Utils
open HTTP_utils
open String_utils
open Lwt.Infix

let parse_quantity table table_name =
  let regexp = {|.*TOP \([0-9]*\)|} in
  if string_match ~regexp table then
    Str.matched_group 1 table |> Int.of_string |> Lwt.return_ok
  else Lwt.return_error (f "parsing %s table." table_name)

module BenchResults = struct
  type t =
    { summary_table: string
    ; failures: string
    ; slow_table: string
    ; slow_number: int
    ; fast_table: string
    ; fast_number: int }
end

(******************************************************************************)
(* CI Job Info and Benchmark Utilities                                        *)
(******************************************************************************)

let fetch_bench_results ~job_info () =
  let open BenchResults in
  let open Lwt.Syntax in
  let artifact_url file =
    f
      "https://coq.gitlabpages.inria.fr/-/coq/-/jobs/%d/artifacts/_bench/timings/%s"
      job_info.build_id file
  in
  let* summary_table = artifact_url "bench_summary" |> fetch_artifact in
  let* failures =
    let* failures_or_err = artifact_url "bench_failures" |> fetch_artifact in
    match failures_or_err with
    | Ok s ->
        Lwt.return s
    | Error err ->
        Lwt_io.printlf "Error fetching bench_failures: %s" err
        >>= fun () -> Lwt.return ""
  in
  let* slow_table =
    let* slow_table_or_err = artifact_url "slow_table.html" |> fetch_artifact in
    match slow_table_or_err with
    | Ok s ->
        Lwt.return s
    | Error _ -> (
        let* slow_table_or_err = artifact_url "slow_table" |> fetch_artifact in
        match slow_table_or_err with
        | Ok s ->
            Lwt.return (String_utils.code_wrap s)
        | Error err ->
            Lwt_io.printlf "Error fetching slow_table: %s" err
            >>= fun () -> Lwt.return "" )
  in
  let* fast_table =
    let* fast_table_or_err = artifact_url "fast_table.html" |> fetch_artifact in
    match fast_table_or_err with
    | Ok s ->
        Lwt.return s
    | Error _ -> (
        let* fast_table_or_err = artifact_url "fast_table" |> fetch_artifact in
        match fast_table_or_err with
        | Ok s ->
            Lwt.return (String_utils.code_wrap s)
        | Error err ->
            Lwt_io.printlf "Error fetching fast_table: %s" err
            >>= fun () -> Lwt.return "" )
  in
  match summary_table with
  | Error e ->
      Lwt.return_error
        (f "Could not fetch table artifacts for bench summary: %s\n" e)
  | Ok summary_table -> (
      (* The tables include how many entries there are, this is useful
         information to know. *)
      let* slow_number = parse_quantity slow_table "slow" in
      let* fast_number = parse_quantity fast_table "fast" in
      match (slow_number, fast_number) with
      | Error e, _ | _, Error e ->
          Lwt.return_error (f "Fetch bench regex issue: %s" e)
      | Ok slow_number, Ok fast_number ->
          Lwt.return_ok
            { summary_table
            ; failures
            ; slow_table
            ; slow_number
            ; fast_table
            ; fast_number } )

let bench_text = function
  | Ok results ->
      (* Formatting helpers *)
      let header2 str = f "## %s" str in
      (* Document *)
      let open BenchResults in
      [ header2 ":checkered_flag: Bench Summary:"
      ; code_wrap results.summary_table
      ; results.failures
      ; header2 @@ f ":turtle: Top %d slow downs:" results.slow_number
      ; results.slow_table
      ; header2 @@ f ":rabbit2: Top %d speed ups:" results.fast_number
      ; results.fast_table ]
      |> String.concat ~sep:"\n" |> Lwt.return
  | Error e ->
      f "Error occured when creating bench summary: %s\n" e |> Lwt.return

let bench_comment ~bot_info ~owner ~repo ~number ~gitlab_url ?check_url
    (results : (BenchResults.t, string) Result.t) =
  GitHub_queries.get_pull_request_id ~bot_info ~owner ~repo ~number
  >>= function
  | Ok id -> (
    match results with
    | Ok results -> (
        [ ":checkered_flag: Bench results:"
        ; String_utils.code_wrap results.summary_table
        ; results.failures
        ; String_utils.markdown_details
            (f ":turtle: Top %d slow downs" results.slow_number)
            results.slow_table
        ; String_utils.markdown_details
            (f ":rabbit2: Top %d speed ups" results.fast_number)
            results.fast_table
        ; "- "
          ^ String_utils.markdown_link ":chair: GitLab Bench Job" gitlab_url ]
        @ Option.value_map
            ~f:(fun x ->
              [ "- "
                ^ String_utils.markdown_link
                    ":spiral_notepad: Bench Check Summary" x ] )
            ~default:[] check_url
        |> String.concat ~sep:"\n"
        |> fun message ->
        GitHub_mutations.post_comment ~bot_info ~id ~message
        >>= function
        | Ok _ ->
            Lwt.return_unit
        | Error e ->
            Lwt_io.printlf "Unable to post bench comment for pr #%d: %s" number
              e )
    | Error e ->
        Lwt_io.printlf "Unable to fetch_results for bench for pr #%d: %s" number
          e )
  | Error e ->
      Lwt_io.printlf "Unable to get_pull_request_id for bench for pr #%d: %s"
        number e

let update_bench_status ~bot_info ~job_info (gh_owner, gh_repo) ~external_id
    ~number =
  let open Lwt.Syntax in
  match number with
  | None ->
      Lwt_io.printlf "No PR number provided for bench summary so aborting."
  | Some number -> (
      GitHub_queries.get_repository_id ~bot_info ~owner:gh_owner ~repo:gh_repo
      >>= function
      | Error e ->
          Lwt_io.printlf "No repo id for bench job: %s" e
      | Ok repo_id -> (
          Lwt_io.printl "Pushing status check for bench job."
          <&>
          let gitlab_url =
            f "https://gitlab.inria.fr/coq/coq/-/jobs/%d" job_info.build_id
          in
          let summary =
            f "## GitLab Job URL:\n[GitLab Bench Job](%s)\n" gitlab_url
          in
          let state = job_info.build_status in
          let context = "bench" in
          let create_check_run ~status ?conclusion ~title ?(text = "") () =
            GitHub_mutations.create_check_run ~bot_info ~name:context ~status
              ~repo_id ~head_sha:job_info.common_info.head_commit ?conclusion
              ~title ~details_url:gitlab_url ~summary ~text ~external_id ()
            >>= function
            | Ok url ->
                let* () =
                  Lwt_io.printlf "Bench Check Summary updated: %s" url
                in
                Lwt.return_some url
            | Error e ->
                let* () =
                  Lwt_io.printlf "Bench Check Summary URL missing: %s" e
                in
                Lwt.return_none
          in
          match state with
          | "success" ->
              let* results = fetch_bench_results ~job_info () in
              let* text = bench_text results in
              let* check_url =
                create_check_run ~status:COMPLETED ~conclusion:SUCCESS
                  ~title:"Bench completed successfully" ~text ()
              in
              let* () =
                bench_comment ~bot_info ~owner:gh_owner ~repo:gh_repo ~number
                  ~gitlab_url ?check_url results
              in
              Lwt.return_unit
          | "failed" ->
              let* results = fetch_bench_results ~job_info () in
              let* text = bench_text results in
              let* check_url =
                create_check_run ~status:COMPLETED ~conclusion:NEUTRAL
                  ~title:"Bench completed with failures" ~text ()
              in
              let* () =
                bench_comment ~bot_info ~owner:gh_owner ~repo:gh_repo ~number
                  ~gitlab_url ?check_url results
              in
              Lwt.return_unit
          | "running" ->
              let* _ =
                create_check_run ~status:IN_PROGRESS ~title:"Bench in progress"
                  ()
              in
              Lwt.return_unit
          | "cancelled" | "canceled" ->
              let* _ =
                create_check_run ~status:COMPLETED ~conclusion:CANCELLED
                  ~title:"Bench has been cancelled" ()
              in
              Lwt.return_unit
          | "created" ->
              Lwt_io.printlf "Bench job has been created, ignoring info update."
          | _ ->
              Lwt_io.printlf "Unknown state for bench job: %s" state ) )

let run_bench ~bot_info ?(org = "rocq-prover") ?(team = "contributors")
    ?(gitlab_domain = "gitlab.inria.fr") ?key_value_pairs comment_info =
  (* Do we want to use this more often? *)
  let open Lwt.Syntax in
  let pr = comment_info.issue in
  let owner = pr.issue.owner in
  let repo = pr.issue.repo in
  let pr_number = pr.number in
  (* We need the GitLab build_id and project_id. Currently there is no good way
     to query this data so we have to jump through some somewhat useless hoops in
     order to get our hands on this information. TODO: do this more directly.*)
  let* gitlab_check_summary =
    GitHub_queries.get_pull_request_refs ~bot_info ~owner ~repo
      ~number:pr_number
    >>= function
    | Error err ->
        Lwt.return_error
          (f
             "Error while fetching PR refs for %s/%s#%d for running bench job: \
              %s"
             owner repo pr_number err )
    | Ok {base= _; head= {sha= head}} ->
        let head = Str.global_replace (Str.regexp {|"|}) "" head in
        GitHub_queries.get_pipeline_summary ~bot_info ~owner ~repo ~head
  in
  (* Parsing the summary into (build_id, project_id) *)
  let* process_summary =
    match gitlab_check_summary with
    | Error err ->
        Lwt.return_error err
    | Ok summary -> (
      try
        let build_id =
          let regexp =
            f {|.*%s\([0-9]*\)|}
              (Str.quote "[bench](https://gitlab.inria.fr/coq/coq/-/jobs/")
          in
          ( if String_utils.string_match ~regexp summary then
              Str.matched_group 1 summary
            else raise @@ Stdlib.Failure "Could not find GitLab bench job ID" )
          |> Stdlib.int_of_string
        in
        let project_id =
          let regexp = {|.*GitLab Project ID: \([0-9]*\)|} in
          ( if String_utils.string_match ~regexp summary then
              Str.matched_group 1 summary
            else raise @@ Stdlib.Failure "Could not find GitLab Project ID" )
          |> Int.of_string
        in
        Lwt.return_ok (build_id, project_id)
      with Stdlib.Failure s ->
        Lwt.return_error
          (f
             "Error while regexing summary for %s/%s#%d for running bench job: \
              %s"
             owner repo pr_number s ) )
  in
  let* allowed_to_bench =
    GitHub_queries.get_team_membership ~bot_info ~org ~team
      ~user:comment_info.author
  in
  match (allowed_to_bench, process_summary) with
  | Ok true, Ok (build_id, project_id) ->
      (* Permission to bench has been granted *)
      GitLab_mutations.play_job ~bot_info ~gitlab_domain ~project_id ~build_id
        ?key_value_pairs ()
  | Error err, _ | _, Error err ->
      GitHub_mutations.post_comment ~bot_info ~message:err ~id:pr.id
      >>= Utils.report_on_posting_comment
  | Ok false, _ ->
      (* User not found in the team *)
      GitHub_automation.inform_user_not_in_contributors ~bot_info ~comment_info
