val send_doc_url :
     bot_info:Bot_components.Bot_info.t
  -> github_repo_full_name:string
  -> Bot_components.GitLab_types.ci_common_info
     Bot_components.GitLab_types.job_info
  -> unit Lwt.t
