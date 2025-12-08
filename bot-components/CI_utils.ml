open Base
open GitLab_types
open GitHub_types
open Utils

(******************************************************************************)
(* Pipeline Summary and Error Formatting                                      *)
(******************************************************************************)

let create_pipeline_summary ?summary_top pipeline_info pipeline_url =
  let variables =
    List.map pipeline_info.variables ~f:(fun (key, value) ->
        f "- %s: %s" key value )
    |> String.concat ~sep:"\n"
  in
  let sorted_builds =
    pipeline_info.builds
    |> List.sort ~compare:(fun build1 build2 ->
           String.compare build1.build_name build2.build_name )
  in
  let stage_summary =
    pipeline_info.stages
    |> List.concat_map ~f:(fun stage ->
           sorted_builds
           |> List.filter_map ~f:(fun build ->
                  if String.equal build.stage stage then
                    Some
                      (f "  - [%s](%s/-/jobs/%d)" build.build_name
                         pipeline_info.common_info.http_repo_url build.build_id )
                  else None )
           |> List.cons ("- " ^ stage) )
    |> String.concat ~sep:"\n"
  in
  [ f "This [GitLab pipeline](%s) sets the following variables:" pipeline_url
  ; variables
  ; "It contains the following stages and jobs:"
  ; stage_summary
  ; f "GitLab Project ID: %d" pipeline_info.common_info.project_id ]
  |> (match summary_top with Some text -> List.cons text | None -> Fn.id)
  |> String.concat ~sep:"\n\n"

let run_ci_minimization_error_to_string = function
  | ArtifactError
      { url= artifact_url
      ; artifact= ArtifactInfo {artifact_owner; artifact_repo; artifact_id}
      ; artifact_error } -> (
    match artifact_error with
    | ArtifactEmpty ->
        f "Could not resume minimization with [empty artifact](%s)" artifact_url
    | ArtifactContainsMultipleFiles filenames ->
        f
          "Could not resume minimization because [artifact](%s) contains more \
           than one file: %s"
          artifact_url
          (String.concat ~sep:", " filenames)
    | ArtifactDownloadError error ->
        f
          "Could not resume minimization because [artifact %s/%s:%s](%s) \
           failed to download:\n\
           %s"
          artifact_owner artifact_repo artifact_id artifact_url error )
  | DownloadError {url; error} ->
      f
        "Could not resume minimization because [artifact](%s) failed to \
         download:\n\
         %s"
        url error

(******************************************************************************)
(* CI Minimization Parsing Utilities                                         *)
(******************************************************************************)

let parse_quantity table table_name =
  let regexp = {|.*TOP \([0-9]*\)|} in
  if string_match ~regexp table then
    Str.matched_group 1 table |> Int.of_string |> Lwt.return_ok
  else Lwt.return_error (f "parsing %s table." table_name)

let shorten_ci_check_name target =
  target
  |> Str.global_replace (Str.regexp "GitLab CI job") ""
  |> Str.global_replace (Str.regexp "(pull request)") ""
  |> Str.global_replace (Str.regexp "(branch)") ""
  |> Stdlib.String.trim

let format_options_for_getopts options =
  " " ^ options ^ " " |> Str.global_replace (Str.regexp "[\n\r\t]") " "

let getopts options ~opt =
  map_string_matches
    ~regexp:(f " %s\\(\\.\\|[ =:-]\\|: \\)\\([^ ]+\\) " opt)
    ~f:(fun () -> Str.matched_group 2 options)
    options

let getopt options ~opt =
  options |> getopts ~opt |> List.hd |> Option.value ~default:""

let accumulate_extra_minimizer_arguments options =
  let extra_args = getopts ~opt:"extra-arg" options in
  let inline_stdlib = getopt ~opt:"inline-stdlib" options in
  ( if String.equal inline_stdlib "yes" then Lwt.return ["--inline-coqlib"]
    else
      ( if not (String.equal inline_stdlib "") then
          Lwt_io.printlf
            "Ignoring invalid option to inline-stdlib '%s' not equal to 'yes'"
            inline_stdlib
        else Lwt.return_unit )
      >>= fun () -> Lwt.return_nil )
  >>= fun inline_stdlib_args -> inline_stdlib_args @ extra_args |> Lwt.return

(******************************************************************************)
(* GitHub Artifact Parsing                                                   *)
(******************************************************************************)

let parse_github_artifact_url url =
  let github_prefix = "https://github.com/" in
  let regexp =
    Str.quote github_prefix
    ^ "\\([^/]+\\)/\\([^/]+\\)/\\(actions/runs\\|suites\\)/.*/artifacts/\\([0-9]+\\)"
  in
  if string_match ~regexp url then
    Some
      (ArtifactInfo
         { artifact_owner= Str.matched_group 1 url
         ; artifact_repo= Str.matched_group 2 url
         ; artifact_id= Str.matched_group 4 url } )
  else None

(******************************************************************************)
(* CI Status Check Functions                                                 *)
(******************************************************************************)

let send_status_check ~bot_info job_info ~pr_num (gh_owner, gh_repo)
    ~github_repo_full_name:_ ~gitlab_domain ~gitlab_repo_full_name ~context
    ~failure_reason ~external_id ~trace =
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
  let rocq_job_info =
    let open Option in
    find_regex_in_lines
      ~regexps:
        [ "^Using Docker executor with image \\([^ ]+\\)"
        ; "options=Options(docker='\\([^']+\\)')" ]
      trace_lines
    >>= fun docker_image ->
    let dependencies =
      find_all_regex_in_lines
        ~regexps:["^Downloading artifacts for \\([^ ]+\\)"]
        trace_lines
    in
    (* The CI script prints "CI_TARGETS=foo bar" through "env" if it is non-default,
       then "CI_TARGETS = foo bar" even if it is the default (from job name).
       We use the later. *)
    find_regex_in_lines ~regexps:["^CI_TARGETS = \\(.*\\)"] trace_lines
    >>= fun targets ->
    let targets = String.split ~on:' ' targets in
    find_regex_in_lines ~regexps:["^COMPILER=\\(.*\\)"] trace_lines
    >>= fun compiler ->
    find_regex_in_lines ~regexps:["^OPAM_VARIANT=\\(.*\\)"] trace_lines
    >>= fun opam_variant ->
    Some {docker_image; dependencies; targets; compiler; opam_variant}
  in
  let* summary_tail_prefix =
    match rocq_job_info with
    | Some {docker_image; dependencies; targets; compiler; opam_variant} ->
        let switch_name = compiler ^ opam_variant in
        let dependencies = String.concat ~sep:"` `" dependencies in
        let targets = String.concat ~sep:"` `" targets in
        Lwt.return
          (f
             "This job ran on the Docker image `%s` with OCaml `%s` and \
              depended on jobs `%s`. It built targets `%s`.\n\n"
             docker_image switch_name dependencies targets )
    | None ->
        Lwt.return ""
  in
  let summary_tail = summary_tail_prefix ^ trace_description in
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
    <&>
    (* If we are in a PR branch, we can post a comment. *)
    if String.equal job_info.build_name "library:ci-fiat_crypto_legacy" then
      let message =
        f "The job [%s](%s) has failed in allow failure mode\nping @JasonGross"
          job_info.build_name job_url
      in
      match pr_num with
      | Some number -> (
          GitHub_queries.get_pull_request_refs ~bot_info ~owner:gh_owner
            ~repo:gh_repo ~number
          >>= function
          | Ok {issue= id; head}
          (* Commits reported back by get_pull_request_refs are surrounded in double quotes *)
            when String.equal head.sha
                   (f {|"%s"|} job_info.common_info.head_commit) ->
              GitHub_mutations.post_comment ~bot_info ~id ~message
              >>= Utils.report_on_posting_comment
          | Ok {head} ->
              Lwt_io.printf
                "We are on a PR branch but the commit (%s) is not the current \
                 head of the PR (%s). Doing nothing.\n"
                job_info.common_info.head_commit head.sha
          | Error err ->
              Lwt_io.printf
                "Couldn't get a database id for %s#%d because the following \
                 error occured:\n\
                 %s\n"
                gitlab_repo_full_name number err )
      | None ->
          Lwt_io.printf "We are not on a PR branch. Doing nothing.\n"
    else Lwt.return_unit
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
(* CI Minimization Core Functions                                            *)
(******************************************************************************)

(* For grammatical correctness, all messages are expected to follow "because" *)
let ci_minimization_suggest ~base
    { base_job_failed
    ; base_job_errored
    ; head_job_succeeded
    ; missing_error
    ; non_v_file
    ; job_kind
    ; job_target } =
  if head_job_succeeded then Bad "job succeeded!"
  else if missing_error then Bad "no error message was found"
  else
    match (base_job_errored, non_v_file) with
    | _, Some filename ->
        Bad (f "error message did not occur in a .v file (%s)" filename)
    | Some err, _ ->
        Possible (f "base job at %s errored with message %s" base err)
    | None, None ->
        if base_job_failed then Possible (f "base job at %s failed" base)
        else if
          not (List.exists ~f:(String.equal job_kind) ["library"; "plugin"])
        then
          Possible
            (f "the job is a %s which is not a library nor a plugin" job_kind)
        else if String.equal job_target "ci-coq_tools" then
          Possible
            (f
               "coq-tools is too sensitive to the output of coqc to be \
                minimized at this time (instead, @JasonGross can help diagnose \
                and fix the issue)" )
        else Suggested

let suggest_ci_minimization_for_pr = function
  (* don't suggest if there are failed test-suite jobs (TODO: decide about async?) *)
  | {failed_test_suite_jobs= _ :: _ as failed_test_suite_jobs} ->
      Silent
        (f "the following test-suite jobs failed: %s"
           (String.concat ~sep:", " failed_test_suite_jobs) )
  (* This next case is a dummy case so OCaml doesn't complain about us
     never using RunAutomatically; we should probably remove it when
     we add a criterion for running minimization automatically *)
  | {labels}
    when List.exists ~f:(String.equal "coqbot request ci minimization") labels
    ->
      RunAutomatically
  | {labels} when List.exists ~f:(String.equal "kind: infrastructure") labels ->
      Silent "this PR is labeled with kind: infrastructure"
  | {body} when not (String.is_substring ~substring:"offer-minimizer: on" body)
    ->
      Silent
        "the PR body does not contain an 'offer-minimizer: on' directive, \
         which turns on minimization suggestions"
  | {draft= true} ->
      Suggest
  | _ ->
      Suggest

let ci_minimization_extract_job_specific_info ~head_pipeline_summary
    ~base_pipeline_summary ~base_checks_errors ~base_checks = function
  | ( {name= full_name; summary= Some summary; text= Some text}
    , head_job_succeeded ) ->
      let base_job_errored =
        List.find_map
          ~f:(fun (base_name, err) ->
            if String.equal full_name base_name then Some err else None )
          base_checks_errors
      in
      let base_job_failed =
        List.exists
          ~f:(fun ({name= base_name}, success_base) ->
            String.equal full_name base_name && not success_base )
          base_checks
      in
      if string_match ~regexp:"\\([^: ]*\\):\\(ci-[A-Za-z0-9_-]*\\)" full_name
      then
        let name = Str.matched_group 0 full_name in
        let job_kind = Str.matched_group 1 full_name in
        let target = Str.matched_group 2 full_name in
        let extract_artifact_url job_name summary =
          if
            string_match
              ~regexp:(f "\\[%s\\](\\([^)]+\\))" (Str.quote job_name))
              summary
          then Some (Str.matched_group 1 summary ^ "/artifacts/download")
          else None
        in
        let collapse_summary name summary =
          f "<details><summary>%s</summary>\n\n%s\n</details>\n" name summary
        in
        if
          string_match
            ~regexp:
              "This job ran on the Docker image `\\([^`]+\\)` with OCaml \
               `\\([^`]+\\)` and depended on jobs \\(\\(`[^`]+` ?\\)+\\). It \
               built targets \\(\\(`[^`]+` ?\\)+\\).\n\n"
            summary
        then
          let docker_image, opam_switch, dependencies, targets =
            ( Str.matched_group 1 summary
            , Str.matched_group 2 summary
            , Str.matched_group 3 summary
            , Str.matched_group 5 summary )
          in
          let dependencies = Str.split (Str.regexp "[ `]+") dependencies in
          let ci_targets = Str.split (Str.regexp "[ `]+") targets in
          let missing_error, non_v_file =
            if
              string_match
                ~regexp:
                  "\n\
                   File \"\\([^\"]*\\)\", line [0-9]*, characters [0-9]*-[0-9]*:\n\
                   Error:"
                text
            then
              let filename = Str.matched_group 1 text in
              ( false
              , if String.is_suffix ~suffix:".v" filename then None
                else Some filename )
            else (true, None)
          in
          let extract_artifacts url =
            List.partition_map
              ~f:(fun name ->
                match extract_artifact_url name url with
                | Some v ->
                    First v
                | None ->
                    Second name )
              (name :: dependencies)
          in
          match
            ( extract_artifacts base_pipeline_summary
            , extract_artifacts head_pipeline_summary )
          with
          | (base_urls, []), (head_urls, []) ->
              Ok
                ( { base_job_failed
                  ; base_job_errored
                  ; missing_error
                  ; non_v_file
                  ; job_kind
                  ; head_job_succeeded
                  ; job_target= target }
                , { target
                  ; full_target= name
                  ; ci_targets
                  ; docker_image
                  ; opam_switch
                  ; failing_urls= String.concat ~sep:" " head_urls
                  ; passing_urls= String.concat ~sep:" " base_urls } )
          | (_, (_ :: _ as base_failed)), _ ->
              Error
                (f "Could not find base dependencies artifacts for %s in:\n%s"
                   (String.concat ~sep:" " base_failed)
                   (collapse_summary "Base Pipeline Summary"
                      base_pipeline_summary ) )
          | _, (_, (_ :: _ as head_failed)) ->
              Error
                (f "Could not find head dependencies artifacts for %s in:\n%s"
                   (String.concat ~sep:" " head_failed)
                   (collapse_summary "Head Pipeline Summary"
                      head_pipeline_summary ) )
        else
          Error
            (f "Could not find needed parameters for job %s in summary:\n%s\n"
               name
               (collapse_summary "Summary" summary) )
      else
        Error (f "Could not separate '%s' into job_kind:ci-target." full_name)
  | {name; summary= None}, _ ->
      Error (f "Could not find summary for job %s." name)
  | {name; text= None}, _ ->
      Error (f "Could not find text for job %s." name)

let fetch_ci_minimization_info ~bot_info ~owner ~repo ~pr_number
    ~head_pipeline_summary ?base_sha ?head_sha () =
  let open Lwt.Syntax in
  let* () =
    Lwt_io.printlf "I'm going to look for failed tests to minimize on PR #%d."
      pr_number
  in
  let* refs =
    match (base_sha, head_sha) with
    | None, _ | _, None ->
        let open Lwt_result.Syntax in
        let+ {base= {sha= base}; head= {sha= head}} =
          GitHub_queries.get_pull_request_refs ~bot_info ~owner ~repo
            ~number:pr_number
        in
        (base, head)
    | Some base, Some head ->
        Lwt.return_ok (base, head)
  in
  match refs with
  | Error err ->
      Lwt.return_error
        ( None
        , f "Error while fetching PR refs for %s/%s#%d for CI minimization: %s"
            owner repo pr_number err )
  | Ok (base, head) -> (
      (* TODO: figure out why there are quotes, cf https://github.com/rocq-prover/bot/issues/61 *)
      let base = Str.global_replace (Str.regexp {|"|}) "" base in
      let head = Str.global_replace (Str.regexp {|"|}) "" head in
      GitHub_queries.get_base_and_head_checks ~bot_info ~owner ~repo ~pr_number
        ~base ~head
      >>= function
      | Error err ->
          Lwt.return_error
            ( None
            , f "Error while looking for failed library tests to minimize: %s"
                err )
      | Ok {pr_id; base_checks; head_checks; draft; body; labels} -> (
          let partition_errors =
            List.partition_map ~f:(function
              | Error (name, error) ->
                  Either.First (shorten_ci_check_name name, error)
              | Ok (result, status) ->
                  Either.Second
                    ( {result with name= shorten_ci_check_name result.name}
                    , status ) )
          in
          let base_checks_errors, base_checks = partition_errors base_checks in
          let head_checks_errors, head_checks = partition_errors head_checks in
          head_checks_errors
          |> Lwt_list.iter_p (fun (_, error) ->
                 Lwt_io.printlf
                   "Non-fatal error while looking for failed tests of PR #%d \
                    to minimize: %s"
                   pr_number error )
          >>= fun () ->
          let extract_pipeline_check =
            List.partition3_map ~f:(fun (check_tab_info, success) ->
                if
                  String.is_prefix ~prefix:"GitLab CI pipeline"
                    check_tab_info.name
                then `Fst (check_tab_info, Option.is_some success)
                else
                  match success with
                  | Some success ->
                      `Snd (check_tab_info, success)
                  | None ->
                      `Trd check_tab_info )
          in
          let extract_pipeline_check_errors =
            List.filter ~f:(fun (name, _) ->
                String.is_prefix ~prefix:"GitLab CI pipeline" name )
          in
          match
            ( ( extract_pipeline_check base_checks
              , extract_pipeline_check_errors base_checks_errors )
            , ( (head_pipeline_summary, true)
              , extract_pipeline_check head_checks
              , extract_pipeline_check_errors head_checks_errors ) )
          with
          | ( ( ( [ ( {summary= Some base_pipeline_summary}
                    , base_pipeline_finished ) ]
                , base_checks
                , unfinished_base_checks )
              , _base_pipeline_checks_errors )
            , ( ( (Some head_pipeline_summary, head_pipeline_finished)
                , (_, head_checks, unfinished_head_checks)
                , _head_pipeline_checks_errors )
              | ( (None, _)
                , ( [ ( {summary= Some head_pipeline_summary}
                      , head_pipeline_finished ) ]
                  , head_checks
                  , unfinished_head_checks )
                , _head_pipeline_checks_errors ) ) ) ->
              Lwt_io.printf
                "Looking for failed tests to minimize among %d head checks (%d \
                 base checks) (head checks: %s) (unfinished head checks: %s) \
                 (base checks: %s) (unfinished base checks: %s).\n"
                (List.length head_checks) (List.length base_checks)
                ( head_checks
                |> List.map ~f:(fun ({name}, _) -> name)
                |> String.concat ~sep:", " )
                ( unfinished_head_checks
                |> List.map ~f:(fun {name} -> name)
                |> String.concat ~sep:", " )
                ( base_checks
                |> List.map ~f:(fun ({name}, _) -> name)
                |> String.concat ~sep:", " )
                ( unfinished_base_checks
                |> List.map ~f:(fun {name} -> name)
                |> String.concat ~sep:", " )
              >>= fun () ->
              let failed_test_suite_jobs =
                List.filter_map head_checks ~f:(fun ({name}, success) ->
                    if string_match ~regexp:"test-suite" name && not success
                    then Some name
                    else None )
                @ List.filter_map head_checks_errors ~f:(fun (name, _) ->
                      if string_match ~regexp:"test-suite" name then Some name
                      else None )
              in
              let possible_jobs_to_minimize, unminimizable_jobs =
                head_checks
                |> List.partition_map ~f:(fun (({name}, _) as head_check) ->
                       match
                         ci_minimization_extract_job_specific_info
                           ~head_pipeline_summary ~base_pipeline_summary
                           ~base_checks_errors ~base_checks head_check
                       with
                       | Error err ->
                           Either.Second (name, err)
                       | Ok result ->
                           Either.First result )
              in
              let unminimizable_jobs =
                unminimizable_jobs
                @ ( unfinished_head_checks
                  |> List.map ~f:(fun {name} ->
                         (name, f "Job %s is still in progress." name) ) )
              in
              Lwt.return_ok
                ( { comment_thread_id= pr_id
                  ; base
                  ; head
                  ; pr_number
                  ; draft
                  ; body
                  ; labels
                  ; base_pipeline_finished
                  ; head_pipeline_finished
                  ; failed_test_suite_jobs }
                , possible_jobs_to_minimize
                , unminimizable_jobs )
          | ((_, _, _), _), ((None, _), ([({summary= None}, _)], _, _), _) ->
              Lwt.return_error
                ( Some pr_id
                , f
                    "Could not find pipeline check summary for head commit %s \
                     and no summary was passed."
                    head )
          | ((_, _, _), _), ((None, _), ([], _, _), [])
            when List.is_empty head_checks_errors ->
              Lwt.return_error
                ( Some pr_id
                , f
                    "Could not find pipeline check for head commit %s and no \
                     summary was passed.  (Found checks: %s)"
                    head
                    ( head_checks
                    |> List.map ~f:(fun ({name}, _) -> name)
                    |> String.concat ~sep:", " ) )
          | ((_, _, _), _), ((None, _), ([], _, _), []) ->
              Lwt.return_error
                ( Some pr_id
                , f
                    "Could not find pipeline check for head commit %s and no \
                     summary was passed.  (Found checks: %s) (Errored while \
                     finding checks: %s)"
                    head
                    ( head_checks
                    |> List.map ~f:(fun ({name}, _) -> name)
                    |> String.concat ~sep:", " )
                    ( head_checks_errors
                    |> List.map ~f:(fun (name, _) -> name)
                    |> String.concat ~sep:", " ) )
          | ( ((_, _, _), _)
            , ((None, _), ([], _, _), [(_head_check_name, head_check_error)]) )
            ->
              Lwt.return_error
                ( Some pr_id
                , f
                    "Could not successfully find pipeline check for head \
                     commit %s and no summary was passed. Error: %s"
                    head head_check_error )
          | ( ((_, _, _), _)
            , ( (None, _)
              , ([], _, _)
              , (_ :: _ :: _ as head_pipeline_checks_errors) ) ) ->
              Lwt.return_error
                ( Some pr_id
                , f
                    "Could not successfully find pipeline check for head \
                     commit %s and no summary was passed. Found multiple \
                     errors on head pipeline checks:\n\
                     %s"
                    head
                    ( head_pipeline_checks_errors
                    |> List.map ~f:(fun (name, error) ->
                           f "- %s: %s" name error )
                    |> String.concat ~sep:"\n" ) )
          | ( ((_, _, _), _)
            , ((None, _), ((_ :: _ :: _ as pipeline_head_checks), _, _), _) ) ->
              Lwt.return_error
                ( Some pr_id
                , f
                    "Found several pipeline checks instead of one for head \
                     commit %s and no summary was passed.  (Found checks: %s)"
                    head
                    ( pipeline_head_checks
                    |> List.map ~f:(fun ({name}, _) -> name)
                    |> String.concat ~sep:", " ) )
          | (([({summary= None}, _)], _, _), _), ((_, _), (_, _, _), _) ->
              Lwt.return_error
                ( Some pr_id
                , f "Could not find pipeline check summary for base commit %s."
                    base )
          | (([], _, _), []), ((_, _), (_, _, _), _)
            when List.is_empty base_checks_errors ->
              Lwt.return_error
                ( Some pr_id
                , f
                    "Could not find pipeline check for base commit %s.  (Found \
                     checks: %s)"
                    base
                    ( base_checks
                    |> List.map ~f:(fun ({name}, _) -> name)
                    |> String.concat ~sep:", " ) )
          | (([], _, _), []), ((_, _), (_, _, _), _) ->
              Lwt.return_error
                ( Some pr_id
                , f
                    "Could not find pipeline check for base commit %s.  (Found \
                     checks: %s) (Errored while finding checks: %s)"
                    base
                    ( base_checks
                    |> List.map ~f:(fun ({name}, _) -> name)
                    |> String.concat ~sep:", " )
                    ( base_checks_errors
                    |> List.map ~f:(fun (name, _) -> name)
                    |> String.concat ~sep:", " ) )
          | ( ( ([], _, _)
              , [(_base_pipeline_check_name, base_pipeline_check_error)] )
            , ((_, _), (_, _, _), _) ) ->
              Lwt.return_error
                ( Some pr_id
                , f
                    "Could not successfully find pipeline check for base \
                     commit %s.  Error: %s"
                    base base_pipeline_check_error )
          | ( (([], _, _), (_ :: _ :: _ as base_pipeline_checks_errors))
            , ((_, _), (_, _, _), _) ) ->
              Lwt.return_error
                ( Some pr_id
                , f
                    "Could not successfully find pipeline check for base \
                     commit %s. Found multiple errors on base pipeline checks:\n\
                     %s"
                    base
                    ( base_pipeline_checks_errors
                    |> List.map ~f:(fun (name, error) ->
                           f "- %s: %s" name error )
                    |> String.concat ~sep:"\n" ) )
          | ( (((_ :: _ :: _ as pipeline_base_checks), _, _), _)
            , ((_, _), (_, _, _), _) ) ->
              Lwt.return_error
                ( Some pr_id
                , f
                    "Found several pipeline checks instead of one for base \
                     commit %s.  (Found checks: %s)"
                    base
                    ( pipeline_base_checks
                    |> List.map ~f:(fun ({name}, _) -> name)
                    |> String.concat ~sep:", " ) ) ) )
