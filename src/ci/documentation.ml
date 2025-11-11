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
  (* Original: hardcoded "rocq-prover/rocq"
     Now: use repo_config if available, fallback to hardcoded for backward compatibility *)
  let repo_full_name =
    match repo_config with
    | Some config ->
        f "%s/%s" config.github_owner config.github_repo
    | None ->
        "rocq-prover/rocq"
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
    (* Original: hardcoded "https://gitlab.inria.fr/coq/coq/-/jobs/%d"
       Now: use repo_config's gitlab_domain, gitlab_owner, gitlab_repo if available,
            fallback to hardcoded for backward compatibility *)
    let job_url =
      match repo_config with
      | Some config -> (
        match
          (config.gitlab_domain, config.gitlab_owner, config.gitlab_repo)
        with
        | Some domain, Some owner, Some repo ->
            f "https://%s/%s/%s/-/jobs/%d" domain owner repo job_info.build_id
        | _ ->
            f "https://gitlab.inria.fr/coq/coq/-/jobs/%d" job_info.build_id )
      | None ->
          f "https://gitlab.inria.fr/coq/coq/-/jobs/%d" job_info.build_id
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

(* Original logic: hardcoded pattern matching on "rocq-prover/rocq" with specific job names
   and artifact paths.

   Before:
   match (github_repo_full_name, job_info.build_name) with
   | "rocq-prover/rocq", ("doc:refman" | "doc:ci-refman") -> ...
   | "rocq-prover/rocq", "doc:init" -> ...
   | "rocq-prover/rocq", ("doc:stdlib" | "doc:stdlib:dune") -> ...
   | "rocq-prover/rocq", "doc:ml-api:odoc" -> ...
   | _ -> Lwt.return_unit

   Now:
   - If repo_config is provided and matches: use config for job names and artifact paths
   - If repo_config is None or doesn't match: fall back to original hardcoded logic
   This ensures full backward compatibility.
*)
let send_doc_url ~bot_info ~github_repo_full_name ?repo_config job_info =
  let owner, repo =
    match String.split ~on:'/' github_repo_full_name with
    | [o; r] ->
        (o, r)
    | _ ->
        ("", "")
  in
  match repo_config with
  | Some config
    when String.equal config.github_owner owner
         && String.equal config.github_repo repo -> (
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
          send_doc_url_job ~bot_info ?repo_config job_info "refman"
            artifact_path
        else if
          (* Check doc_init - Original: "doc:init" *)
          match jobs.doc_init with
          | Some "doc:init" ->
              String.equal job_info.build_name "doc:init"
          | _ ->
              false
        then
          let artifact_path =
            Option.value ~default:"_build/default/doc/corelib/html/index.html"
              doc.corelib_path
          in
          send_doc_url_job ~bot_info ?repo_config job_info "corelib"
            artifact_path
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
          send_doc_url_job ~bot_info ?repo_config job_info "stdlib"
            artifact_path
        else if
          (* Check doc_ml_api - Original: "doc:ml-api:odoc" *)
          match jobs.doc_ml_api with
          | Some "doc:ml-api:odoc" ->
              String.equal job_info.build_name "doc:ml-api:odoc"
          | _ ->
              false
        then
          let artifact_path =
            Option.value ~default:"_build/default/_doc/_html/index.html"
              doc.ml_api_path
          in
          send_doc_url_job ~bot_info ?repo_config job_info "ml-api"
            artifact_path
        else Lwt.return_unit
    | _ ->
        Lwt.return_unit )
  | _ -> (
    (* No config provided or repo doesn't match - fall back to original hardcoded logic *)
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
        Lwt.return_unit )
