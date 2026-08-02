open Base
open Bot_components
open GitLab_types
open GitHub_types
open Utils
open String_utils
open Git_utils
open Lwt.Infix
open Lwt.Syntax

(******************************************************************************)
(* Types                                                                      *)
(******************************************************************************)

type build_failure = Warn of string | Retry of string | Ignore of string

(******************************************************************************)
(* CI Status Check Functions                                                 *)
(******************************************************************************)

let send_status_check ~bot_info job_info ~pr_num (gh_owner, gh_repo)
    ~gitlab_domain ~gitlab_repo_full_name ~context ~failure_reason ~external_id
    ~trace
    ?(summary_builder = fun _ trace_description -> Lwt.return trace_description)
    ?(allow_failure_handler =
      fun ~bot_info:_
        ~job_name:_
        ~job_url:_
        ~pr_num:_
        ~head_commit:_
        (_gh_owner, _gh_repo)
        ~gitlab_repo_full_name:_
      -> Lwt.return_unit) () =
  let job_url =
    f "https://%s/%s/-/jobs/%d" gitlab_domain gitlab_repo_full_name
      job_info.build_id
  in
  let trace_lines = clean_gitlab_trace trace in
  let title, last_index_of_error =
    (* We try to find the line starting with "Error" only in the case
       of an actual script failure. *)
    match failure_reason with
    | "script_failure" ->
        ( "Test has failed on GitLab CI"
        , trace_lines
          |> List.filter_mapi ~f:(fun i line ->
              if String.is_prefix ~prefix:"Error" line then Some i else None )
          |> List.last )
    | "job_execution_timeout" ->
        ("Test has reached timeout on GitLab CI", None)
    | _ ->
        (failure_reason ^ " on GitLab CI", None)
  in
  let trace_description, short_trace =
    (* If we have a last index of error, we display 40 lines starting
       at the line before (which should include the filename).
       Otherwise, we display only the last 40 lines of the trace *)
    match last_index_of_error with
    | None ->
        ( f
            "We show below the last 40 lines of the trace from GitLab (the \
             complete trace is available [here](%s))."
            job_url
        , trace_lines
          |> Fn.flip List.drop (List.length trace_lines - 40)
          |> String.concat ~sep:"\n" )
    | Some index_of_error ->
        ( f
            "We show below an excerpt from the trace from GitLab starting \
             around the last detected \"Error\" (the complete trace is \
             available [here](%s))."
            job_url
        , trace_lines
          |> Fn.flip List.drop (index_of_error - 1)
          |> Fn.flip List.take 40 |> String.concat ~sep:"\n" )
  in
  let* summary_tail = summary_builder trace_lines trace_description in
  let text = "```\n" ^ short_trace ^ "\n```" in
  if job_info.allow_fail then
    Lwt_io.printf "Job is allowed to fail.\n"
    <&> ( GitHub_queries.get_repository_id ~bot_info ~owner:gh_owner
            ~repo:gh_repo
        >>= function
        | Ok repo_id ->
            let open Lwt.Syntax in
            let+ _ =
              GitHub_mutations.create_check_run ~bot_info ~name:context ~repo_id
                ~head_sha:job_info.common_info.head_commit ~conclusion:NEUTRAL
                ~status:COMPLETED ~title ~details_url:job_url
                ~summary:("This job is allowed to fail.\n\n" ^ summary_tail)
                ~text ~external_id ()
            in
            ()
        | Error e ->
            Lwt_io.printf "No repo id: %s\n" e )
    <&> allow_failure_handler ~bot_info ~job_name:job_info.build_name ~job_url
          ~pr_num ~head_commit:job_info.common_info.head_commit
          (gh_owner, gh_repo) ~gitlab_repo_full_name
  else
    Lwt_io.printf "Pushing a status check...\n"
    <&> ( GitHub_queries.get_repository_id ~bot_info ~owner:gh_owner
            ~repo:gh_repo
        >>= function
        | Ok repo_id ->
            let open Lwt.Syntax in
            let+ _ =
              GitHub_mutations.create_check_run ~bot_info ~name:context ~repo_id
                ~head_sha:job_info.common_info.head_commit ~conclusion:FAILURE
                ~status:COMPLETED ~title ~details_url:job_url
                ~summary:
                  ( "This job has failed. If you need to, you can restart it \
                     directly in the GitHub interface using the \"Re-run\" \
                     button.\n\n" ^ summary_tail )
                ~text ~external_id ()
            in
            ()
        | Error e ->
            Lwt_io.printf "No repo id: %s\n" e )

(******************************************************************************)
(* GitLab Trace Processing Utilities                                          *)
(******************************************************************************)

let trace_action ~repo_full_name trace =
  trace |> String.length
  |> Lwt_io.printlf "Trace size: %d."
  >>= fun () ->
  Lwt.return
    (let test regexp = string_match ~regexp trace in
     if test "Job failed: exit code 137" then Retry "Exit code 137"
     else if test "Job failed: exit status 255" then Retry "Exit status 255"
     else if test "Job failed (system failure)" then Retry "System failure"
     else if
       ( test "Uploading artifacts.*to coordinator... failed"
       || test "Uploading artifacts.*to coordinator... error" )
       && not (test "Uploading artifacts.*to coordinator... ok")
     then Retry "Artifact uploading failure"
     else if
       test "ERROR: Downloading artifacts.*from coordinator... error"
       && test "FATAL: invalid argument"
     then Retry "Artifact downloading failure"
     else if
       test "transfer closed with outstanding read data remaining"
       || test "HTTP request sent, awaiting response... 50[0-9]"
       || test "The requested URL returned error: 502"
       || test "received unexpected HTTP status: 50[0-9]"
       || test "unexpected status from GET request to.*: 50[0-9]"
       || test "error: unable to download 'https://cache.nixos.org/"
       || test "fatal: unable to access .* Couldn't connect to server"
       || test "fatal: unable to access .* Could not resolve host"
       || test "Resolving .* failed: Temporary failure in name resolution"
       || test "unexpected status code .*: 401 Unauthorized"
     then Retry "Connectivity issue"
     else if test "fatal: reference is not a tree" then
       Ignore "Normal failure: pull request was force-pushed."
     else if
       test "fatal: Remote branch pr-[0-9]* not found in upstream origin"
       || test "fatal: [Cc]ouldn't find remote ref refs/heads/pr-"
     then Ignore "Normal failure: pull request was closed."
     else if
       String.equal repo_full_name "coq/coq"
       && test "Error response from daemon: manifest for .* not found"
     then Ignore "Docker image not found. Do not report anything specific."
     else Warn trace )

let job_failure ~bot_info job_info ~pr_num (gh_owner, gh_repo) ~gitlab_domain
    ~gitlab_repo_full_name ~context ~failure_reason ~external_id
    ?summary_builder ?allow_failure_handler () =
  let build_id = job_info.build_id in
  let project_id =
    (job_info.common_info : Bot_components.GitLab_types.ci_common_info)
      .project_id
  in
  Lwt_io.printf "Failed job %d of project %d.\nFailure reason: %s\n" build_id
    project_id failure_reason
  >>= fun () ->
  ( if String.equal failure_reason "runner_system_failure" then
      Lwt.return (Retry "Runner failure reported by GitLab CI")
    else
      Lwt_io.printlf
        "Failure reason reported by GitLab CI: %s.\nRetrieving the trace..."
        failure_reason
      >>= fun () ->
      GitLab_queries.get_build_trace ~bot_info ~gitlab_domain ~project_id
        ~build_id
      >>= function
      | Ok trace ->
          trace_action ~repo_full_name:gitlab_repo_full_name trace
      | Error err ->
          Lwt.return (Ignore (f "Error while retrieving the trace: %s." err)) )
  >>= function
  | Warn trace ->
      Lwt_io.printf "Actual failure.\n"
      <&> send_status_check ~bot_info job_info ~pr_num (gh_owner, gh_repo)
            ~gitlab_domain ~gitlab_repo_full_name ~context ~failure_reason
            ~external_id ~trace ?summary_builder ?allow_failure_handler ()
  | Retry reason -> (
      Lwt_io.printlf "%s... Checking whether to retry the job." reason
      >>= fun () ->
      GitLab_queries.get_retry_nb ~bot_info ~gitlab_domain
        ~full_name:gitlab_repo_full_name ~build_id
        ~build_name:job_info.build_name
      >>= function
      | Ok retry_nb when retry_nb < 3 ->
          Lwt_io.printlf
            "The job has been retried less than three times before (number of \
             retries = %d). Retrying..."
            retry_nb
          >>= fun () ->
          GitLab_mutations.retry_job ~bot_info ~gitlab_domain ~project_id
            ~build_id
      | Ok retry_nb ->
          Lwt_io.printlf
            "The job has been retried %d times before. Not retrying." retry_nb
      | Error e ->
          Lwt_io.printlf "Error while getting the number of retries: %s" e )
  | Ignore reason ->
      Lwt_io.printl reason

let job_success_or_pending ~bot_info (gh_owner, gh_repo) job_info ~gitlab_domain
    ~gitlab_repo_full_name ~context ~state ~external_id =
  let {build_id} = job_info in
  GitHub_queries.get_status_check ~bot_info ~owner:gh_owner ~repo:gh_repo
    ~commit:job_info.common_info.head_commit ~context
  >>= function
  | Ok true -> (
      Lwt_io.printf
        "There existed a previous status check for this build, we'll override \
         it.\n"
      <&>
      let job_url =
        f "https://%s/%s/-/jobs/%d" gitlab_domain gitlab_repo_full_name build_id
      in
      let status, conclusion, description =
        match state with
        | "success" ->
            ( COMPLETED
            , Some SUCCESS
            , "Test succeeded on GitLab CI after being retried" )
        | "created" ->
            (QUEUED, None, "Test pending on GitLab CI after being retried")
        | "running" ->
            (IN_PROGRESS, None, "Test running on GitLab CI after being retried")
        | _ ->
            failwith
              (f "Error: job_success_or_pending received unknown state %s."
                 state )
      in
      GitHub_queries.get_repository_id ~bot_info ~owner:gh_owner ~repo:gh_repo
      >>= function
      | Ok repo_id ->
          let open Lwt.Syntax in
          let+ _ =
            GitHub_mutations.create_check_run ~bot_info ~name:context ~status
              ~repo_id ~head_sha:job_info.common_info.head_commit ?conclusion
              ~title:description ~details_url:job_url ~summary:"" ~external_id
              ()
          in
          ()
      | Error e ->
          Lwt_io.printf "No repo id: %s\n" e )
  | Ok _ ->
      Lwt.return_unit
  | Error e ->
      Lwt_io.printf "%s\n" e

let pipeline_action ~bot_info ({common_info= {http_repo_url}} as pipeline_info)
    ~gitlab_mapping ?(full_ci_check_repo = None)
    ?(auto_minimize_on_failure = None) () =
  let pr_number, _ = pr_from_branch pipeline_info.common_info.branch in
  match pipeline_info.state with
  | "skipped" ->
      Lwt.return_unit
  | _ -> (
      let pipeline_url =
        f "%s/-/pipelines/%d" http_repo_url pipeline_info.pipeline_id
      in
      let external_id =
        f "%s,projects/%d/pipelines/%d" http_repo_url
          pipeline_info.common_info.project_id pipeline_info.pipeline_id
      in
      match
        GitHub_GitLab_sync.github_repo_of_gitlab_url ~gitlab_mapping
          ~http_repo_url
      with
      | Error err ->
          Lwt_io.printlf "Error in pipeline action: %s" err
      | Ok (gh_owner, gh_repo) -> (
          let status, conclusion, title, summary_top =
            (* Check if this repo should have full CI detection *)
            let full_ci =
              match full_ci_check_repo with
              | Some (check_owner, check_repo)
                when String.equal check_owner gh_owner
                     && String.equal check_repo gh_repo -> (
                try
                  List.find_map
                    ~f:(fun (key, value) ->
                      if String.equal key "FULL_CI" then
                        Some (Bool.of_string value)
                      else None )
                    pipeline_info.variables
                with _ -> None )
              | _ ->
                  None
            in
            let qualified_pipeline =
              match full_ci with
              | Some true ->
                  "Full pipeline"
              | Some false ->
                  "Light pipeline"
              | None ->
                  "Pipeline"
            in
            match pipeline_info.state with
            | "pending" ->
                ( QUEUED
                , None
                , f "%s is pending on GitLab CI" qualified_pipeline
                , None )
            | "running" ->
                ( IN_PROGRESS
                , None
                , f "%s is running on GitLab CI" qualified_pipeline
                , None )
            | "success" ->
                ( COMPLETED
                , Some
                    ( match full_ci with
                    | Some false ->
                        NEUTRAL
                    | Some true | None ->
                        SUCCESS )
                , f "%s completed successfully on GitLab CI" qualified_pipeline
                , None )
            | "failed" ->
                ( COMPLETED
                , Some FAILURE
                , f "%s completed with errors on GitLab CI" qualified_pipeline
                , Some
                    "*If you need to restart the entire pipeline, you may do \
                     so directly in the GitHub interface using the \"Re-run\" \
                     button.*" )
            | "cancelled" | "canceled" ->
                ( COMPLETED
                , Some CANCELLED
                , f "%s was cancelled on GitLab CI" qualified_pipeline
                , None )
            | s ->
                (COMPLETED, Some FAILURE, "Unknown pipeline status: " ^ s, None)
          in
          GitHub_queries.get_repository_id ~bot_info ~owner:gh_owner
            ~repo:gh_repo
          >>= function
          | Error e ->
              Lwt_io.printf "No repo id: %s\n" e
          | Ok repo_id -> (
              let summary =
                Bot_components.CI_utils.create_pipeline_summary ?summary_top
                  pipeline_info pipeline_url
              in
              GitHub_mutations.create_check_run ~bot_info
                ~name:
                  (f "GitLab CI pipeline (%s)"
                     (pr_from_branch pipeline_info.common_info.branch |> snd) )
                ~repo_id ~head_sha:pipeline_info.common_info.head_commit ~status
                ?conclusion ~title ~details_url:pipeline_url ~summary
                ~external_id ()
              >>= fun _ ->
              Lwt_unix.sleep 5.
              >>= fun () ->
              match
                ( auto_minimize_on_failure
                , gh_owner
                , gh_repo
                , pipeline_info.state
                , pr_number )
              with
              | ( Some (min_owner, min_repo)
                , owner
                , repo
                , "failed"
                , Some pr_number )
                when String.equal owner min_owner && String.equal repo min_repo
                ->
                  Minimization.minimize_failed_tests ~bot_info ~owner:gh_owner
                    ~repo:gh_repo ~pr_number
                    ~head_pipeline_summary:(Some summary)
                    ~request:Minimization.Auto ~comment_on_error:false
                    ~options:"" ~bug_file:None
                    ?base_sha:pipeline_info.common_info.base_commit
                    ~head_sha:pipeline_info.common_info.head_commit ()
              | _ ->
                  Lwt.return_unit ) ) )
