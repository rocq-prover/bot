val merge_pull_request_action :
  bot_info:Bot_info.t -> ?t:float -> GitHub_types.comment_info -> unit Lwt.t

val adjust_milestone :
     bot_info:Bot_info.t
  -> issue:GitHub_types.issue
  -> sleep_time:float
  -> unit Lwt.t

val add_to_column :
     bot_info:Bot_info.t
  -> organization:string
  -> project:int
  -> backport_to:string
  -> [< `Card_ID of GitHub_ID.t | `PR_ID of GitHub_ID.t]
  -> string
  -> unit Lwt.t

val reflect_pull_request_milestone :
  bot_info:Bot_info.t -> GitHub_types.issue_closer_info -> unit Lwt.t

val pull_request_closed_action :
     bot_info:Bot_info.t
  -> GitHub_types.issue_info GitHub_types.pull_request_info
  -> gitlab_mapping:(string, string) Base.Hashtbl.t
  -> github_mapping:(string, string * string) Base.Hashtbl.t
  -> remove_milestone_if_not_merged:bool
  -> unit Lwt.t

val add_remove_labels :
     bot_info:Bot_info.t
  -> add:bool
  -> GitHub_types.issue_info
  -> string list
  -> unit Lwt.t

val add_labels_if_absent :
  bot_info:Bot_info.t -> GitHub_types.issue_info -> string list -> unit

val remove_labels_if_present :
  bot_info:Bot_info.t -> GitHub_types.issue_info -> string list -> unit

val inform_user_not_in_contributors :
  bot_info:Bot_info.t -> comment_info:GitHub_types.comment_info -> unit Lwt.t
