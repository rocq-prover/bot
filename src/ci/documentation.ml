open Base
open Bot_components
open GitLab_types
open Utils
open Cohttp
open Cohttp_lwt_unix
open Lwt.Infix
open Repo_config

let rec send_doc_url_aux ~bot_info ?repo_config job_info ~fallback_urls
    (kind, url) =
  let context = f "%s: %s artifact" job_info.build_name kind in
  let description_base = f "Link to %s build artifact" kind in
  (* Refactored to remove hardcoded repository checks (Step 6.5)

     Before: Had hardcoded fallback to "rocq-prover/rocq".
     Now: Use repo_config (required for this feature). *)
  (* Use repo_config - required, no fallback *)
  let repo_full_name =
    match repo_config with
    | Some config ->
        f "%s/%s" config.github_owner config.github_repo
    | None ->
        failwith "send_doc_url_aux called without repo_config"
  in
  let open Lwt.Syntax in
  let status_code url =
    let+ resp, _ = url |> Uri.of_string |> Client.get in
    resp |> Response.status |> Code.code_of_status
  in
  let success_response url =
    GitHub_mutations.send_status_check ~repo_full_name
      ~commit:job_info.common_info.head_commit ~state:"success" ~url ~context
      ~description:(description_base ^ ".") ~bot_info
  in
  let fail_response code =
    Lwt_io.printf "But we got a %d code when checking the URL.\n" code
    <&>
    (* BEFORE: Had hardcoded fallback to "gitlab.inria.fr/coq/coq" *)
    (* NOW: Use repo_config's gitlab_domain, gitlab_owner, gitlab_repo *)
    let job_url =
      match repo_config with
      | Some config -> (
        match
          (config.gitlab_domain, config.gitlab_owner, config.gitlab_repo)
        with
        | Some domain, Some gl_owner, Some gl_repo ->
            f "https://%s/%s/%s/-/jobs/%d" domain gl_owner gl_repo
              job_info.build_id
        | _ ->
            (* Use defaults if not configured *)
            let domain =
              Option.value ~default:"gitlab.com" config.gitlab_domain
            in
            let gl_owner =
              Option.value ~default:config.github_owner config.gitlab_owner
            in
            let gl_repo =
              Option.value ~default:config.github_repo config.gitlab_repo
            in
            f "https://%s/%s/%s/-/jobs/%d" domain gl_owner gl_repo
              job_info.build_id )
      | None ->
          failwith "send_doc_url_aux called without repo_config"
    in
    GitHub_mutations.send_status_check ~repo_full_name
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
        send_doc_url_aux ~bot_info ?repo_config ~fallback_urls job_info
          (kind, url) )

let send_doc_url_job ~bot_info ?repo_config ?(fallback_artifacts = []) job_info
    doc_key artifact =
  Lwt_io.printf
    "This is a successful %s build. Pushing a status check with a link...\n"
    doc_key
  <&>
  let build_url artifact =
    f "https://coq.gitlabpages.inria.fr/-/coq/-/jobs/%d/artifacts/%s"
      job_info.build_id artifact
  in
  send_doc_url_aux ~bot_info ?repo_config job_info
    ~fallback_urls:(List.map ~f:build_url fallback_artifacts)
    (doc_key, build_url artifact)

(* Refactored to remove hardcoded repository checks

   Before: Had hardcoded pattern matching on "rocq-prover/rocq" with specific job names.
   Now: Use repo_config with jobs and documentation config (required for this feature). *)
let send_doc_url ~bot_info ~github_repo_full_name:_ ?repo_config job_info =
  (* Use repo_config - required, no fallback *)
  match repo_config with
  | Some config -> (
    match (config.jobs, config.documentation) with
    | Some jobs, Some doc ->
        (* Check doc_refman jobs - Original: "doc:refman" | "doc:ci-refman" *)
        if
          match jobs.doc_refman with
          | Some doc_jobs ->
              List.mem doc_jobs job_info.build_name ~equal:String.equal
          | None ->
              false
        then
          let artifact_path =
            Option.value ~default:"_build/default/doc/refman-html/index.html"
              doc.refman_path
          in
          send_doc_url_job ~bot_info ?repo_config:(Some config) job_info
            "refman" artifact_path
        else if
          (* Check doc_init - Original: "doc:init" *)
          match jobs.doc_init with
          | Some doc_init_job ->
              String.equal job_info.build_name doc_init_job
          | None ->
              false
        then
          let artifact_path =
            Option.value ~default:"_build/default/doc/corelib/html/index.html"
              doc.corelib_path
          in
          send_doc_url_job ~bot_info ?repo_config:(Some config) job_info
            "corelib" artifact_path
        else if
          (* Check doc_stdlib - Original: "doc:stdlib" | "doc:stdlib:dune" *)
          match jobs.doc_stdlib with
          | Some doc_jobs ->
              List.mem doc_jobs job_info.build_name ~equal:String.equal
          | None ->
              false
        then
          let artifact_path =
            Option.value ~default:"_build/default/doc/stdlib/html/index.html"
              doc.stdlib_path
          in
          send_doc_url_job ~bot_info ?repo_config:(Some config) job_info
            "stdlib" artifact_path
        else if
          (* Check doc_ml_api - Original: "doc:ml-api:odoc" *)
          match jobs.doc_ml_api with
          | Some doc_ml_api_job ->
              String.equal job_info.build_name doc_ml_api_job
          | None ->
              false
        then
          let artifact_path =
            Option.value ~default:"_build/default/_doc/_html/index.html"
              doc.ml_api_path
          in
          send_doc_url_job ~bot_info ?repo_config:(Some config) job_info
            "ml-api" artifact_path
        else Lwt.return_unit
    | _ ->
        (* No jobs or documentation config - skip (feature not enabled) *)
        Lwt.return_unit )
  | None ->
      (* No config provided - skip (config should always be provided) *)
      Lwt.return_unit
