open Base
open Bot_components
open Bot_components.String_utils
open Utils
open Lwt.Infix

type rocq_job_info =
  { docker_image: string
  ; dependencies: string list
  ; targets: string list
  ; compiler: string
  ; opam_variant: string }

let extract_rocq_job_info trace_lines =
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

let build_rocq_summary_tail rocq_job_info ~trace_description =
  match rocq_job_info with
  | Some {docker_image; dependencies; targets; compiler; opam_variant} ->
      let switch_name = compiler ^ opam_variant in
      let dependencies = String.concat dependencies ~sep:"` `" in
      let targets = String.concat targets ~sep:"` `" in
      f
        "This job ran on the Docker image `%s` with OCaml `%s` and depended on \
         jobs `%s`. It built targets `%s`.\n\n\
         %s"
        docker_image switch_name dependencies targets trace_description
  | None ->
      trace_description

let handle_rocq_allow_failure ~bot_info ~job_name ~job_url ~pr_num ~head_commit
    (gh_owner, gh_repo) ~gitlab_repo_full_name =
  (* If we are in a PR branch, we can post a comment. *)
  if String.equal job_name "library:ci-fiat_crypto_legacy" then
    let message =
      f "The job [%s](%s) has failed in allow failure mode\nping @JasonGross"
        job_name job_url
    in
    match pr_num with
    | Some number -> (
        GitHub_queries.get_pull_request_refs ~bot_info ~owner:gh_owner
          ~repo:gh_repo ~number
        >>= function
        | Ok {issue= id; head}
        (* Commits reported back by get_pull_request_refs are surrounded in double quotes *)
          when String.equal head.sha (f {|"%s"|} head_commit) ->
            GitHub_mutations.post_comment ~bot_info ~id ~message
            >>= Utils.report_on_posting_comment
        | Ok {head} ->
            Lwt_io.printf
              "We are on a PR branch but the commit is not the current head of \
               the PR (%s). Doing nothing.\n"
              head.sha
        | Error err ->
            Lwt_io.printf
              "Couldn't get a database id for %s#%d because the following \
               error occured:\n\
               %s\n"
              gitlab_repo_full_name number err )
    | None ->
        Lwt_io.printf "We are not on a PR branch. Doing nothing.\n"
  else Lwt.return_unit

let rocq_summary_builder trace_lines =
  let rocq_job_info = extract_rocq_job_info trace_lines in
  fun trace_description ->
    Lwt.return (build_rocq_summary_tail rocq_job_info ~trace_description)
