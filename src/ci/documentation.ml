open Base
open Bot_components
open GitLab_types
open Utils
open Cohttp
open Cohttp_lwt_unix
open Lwt.Infix

let rec send_doc_url_aux ~bot_info job_info ~fallback_urls (kind, url) =
  let context = f "%s: %s artifact" job_info.build_name kind in
  let description_base = f "Link to %s build artifact" kind in
  let open Lwt.Syntax in
  let status_code url =
    let+ resp, _ = url |> Uri.of_string |> Client.get in
    resp |> Response.status |> Code.code_of_status
  in
  let success_response url =
    GitHub_mutations.send_status_check ~repo_full_name:"rocq-prover/rocq"
      ~commit:job_info.common_info.head_commit ~state:"success" ~url ~context
      ~description:(description_base ^ ".") ~bot_info
  in
  let fail_response code =
    Lwt_io.printf "But we got a %d code when checking the URL.\n" code
    <&>
    let job_url =
      f "https://gitlab.inria.fr/coq/coq/-/jobs/%d" job_info.build_id
    in
    GitHub_mutations.send_status_check ~repo_full_name:"rocq-prover/rocq"
      ~commit:job_info.common_info.head_commit ~state:"failure" ~url:job_url
      ~context
      ~description:(description_base ^ ": not found.")
      ~bot_info
  in
  let error_code url =
    let+ status_code = status_code url in
    if Int.equal 200 status_code then None else Some status_code
  in
  let* code = error_code url in
  match code with
  | None ->
      success_response url
  | Some code -> (
    match fallback_urls with
    | [] ->
        fail_response code
    | url :: fallback_urls ->
        send_doc_url_aux ~bot_info ~fallback_urls job_info (kind, url) )

let send_doc_url_job ~bot_info ?(fallback_artifacts = []) job_info doc_key
    artifact =
  Lwt_io.printf
    "This is a successful %s build. Pushing a status check with a link...\n"
    doc_key
  <&>
  let build_url artifact =
    f "https://coq.gitlabpages.inria.fr/-/coq/-/jobs/%d/artifacts/%s"
      job_info.build_id artifact
  in
  send_doc_url_aux ~bot_info job_info
    ~fallback_urls:(List.map ~f:build_url fallback_artifacts)
    (doc_key, build_url artifact)

let send_doc_url ~bot_info ~github_repo_full_name job_info =
  match (github_repo_full_name, job_info.build_name) with
  | "rocq-prover/rocq", ("doc:refman" | "doc:ci-refman") ->
      send_doc_url_job ~bot_info job_info "refman"
        "_build/default/doc/refman-html/index.html"
  | "rocq-prover/rocq", "doc:init" ->
      send_doc_url_job ~bot_info job_info "corelib"
        "_build/default/doc/corelib/html/index.html"
  | ( "rocq-prover/rocq"
    , ( "doc:stdlib" (* only after complete switch to Dune *)
      | "doc:stdlib:dune" (* only before complete switch to Dune *) ) ) ->
      send_doc_url_job ~bot_info job_info "stdlib"
        "_build/default/doc/stdlib/html/index.html"
  | "rocq-prover/rocq", "doc:ml-api:odoc" ->
      send_doc_url_job ~bot_info job_info "ml-api"
        "_build/default/_doc/_html/index.html"
  | _ ->
      Lwt.return_unit
