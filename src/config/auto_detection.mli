val auto_detect_org_team :
     bot_info:Bot_components.Bot_info.t
  -> github_owner:string
  -> github_repo:string
  -> (string option * string option) option Lwt.t
(** Auto-detect organization and team from GitHub API with caching *)

val auto_detect_gitlab_info :
     bot_info:Bot_components.Bot_info.t
  -> github_owner:string
  -> github_repo:string
  -> (string * string * string) option Lwt.t
(** Auto-detect GitLab domain by searching all configured GitLab instances *)

val auto_detect_from_apis :
     bot_info:Bot_components.Bot_info.t
  -> github_owner:string
  -> github_repo:string
  -> Repo_config.t Lwt.t
(** Complete auto-detection from API with caching *)
