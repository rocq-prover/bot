open Base
open Bot_components
open Bot_components.GitLab_types
open Bot_components.GitHub_GitLab_sync
open Git_utils
open Utils
open Lwt.Infix

let job_action ~bot_info
    ({build_name; common_info= {http_repo_url}} as job_info) ~gitlab_mapping
    ~repo_config_table =
  let pr_num, branch_or_pr = pr_from_branch job_info.common_info.branch in
  let context = f "GitLab CI job %s (%s)" build_name branch_or_pr in
  match parse_gitlab_repo_url ~http_repo_url with
  | Error e ->
      Lwt_io.printlf "Error in job_action: %s" e
  | Ok (gitlab_domain, gitlab_repo_full_name) -> (
      let gh_owner, gh_repo =
        github_repo_of_gitlab_project_path ~gitlab_mapping ~gitlab_domain
          ~gitlab_repo_full_name
      in
      let github_repo_full_name = gh_owner ^ "/" ^ gh_repo in
      let repo_config =
        Repo_config.find_by_github ~owner:gh_owner ~repo:gh_repo
          repo_config_table
      in
      let external_id =
        f "%s,projects/%d/jobs/%d" http_repo_url job_info.common_info.project_id
          job_info.build_id
      in
      match repo_config with
      | Some cfg when Repo_config.is_bench_job cfg build_name ->
          Bench.update_bench_status ~bot_info ~job_info (gh_owner, gh_repo)
            ~external_id ~number:pr_num
      | _ -> (
        match job_info.build_status with
        | "failed" ->
            let failure_reason = Option.value_exn job_info.failure_reason in
            let summary_builder, allow_failure_handler =
              match repo_config with
              | Some cfg when cfg.jobs.use_rocq_job_status ->
                  ( Job_status_rocq.rocq_summary_builder
                  , fun ~bot_info
                      ~job_name
                      ~job_url
                      ~pr_num
                      ~head_commit
                      (gh_owner, gh_repo)
                      ~gitlab_repo_full_name
                    ->
                      Job_status_rocq.handle_rocq_allow_failure ~bot_info
                        ~job_name ~job_url ~pr_num ~head_commit
                        (gh_owner, gh_repo) ~gitlab_repo_full_name )
              | _ ->
                  ( (fun _trace_lines trace_description ->
                      Lwt.return trace_description )
                  , fun ~bot_info:_
                      ~job_name:_
                      ~job_url:_
                      ~pr_num:_
                      ~head_commit:_
                      _
                      ~gitlab_repo_full_name:_
                    -> Lwt.return_unit )
            in
            Job_status.job_failure ~bot_info job_info ~pr_num
              (gh_owner, gh_repo) ~gitlab_domain ~gitlab_repo_full_name ~context
              ~failure_reason ~external_id ~summary_builder
              ~allow_failure_handler ()
        | "success" as state ->
            Job_status.job_success_or_pending ~bot_info (gh_owner, gh_repo)
              job_info ~gitlab_domain ~gitlab_repo_full_name ~context ~state
              ~external_id
            <&> Documentation.send_doc_url ~bot_info job_info
                  ~github_repo_full_name
        | ("created" | "running") as state ->
            Job_status.job_success_or_pending ~bot_info (gh_owner, gh_repo)
              job_info ~gitlab_domain ~gitlab_repo_full_name ~context ~state
              ~external_id
        | "cancelled" | "canceled" | "pending" ->
            (* Ideally we should check if a status was already reported for
               this job.  But it is important to avoid making dozens of
               requests at once when a pipeline is canceled.  So we should
               have a caching mechanism to limit this case to a single
               request. *)
            Lwt.return_unit
        | unknown_state ->
            Lwt_io.printlf "Unknown job status: %s" unknown_state ) )
