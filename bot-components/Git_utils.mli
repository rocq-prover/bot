val ( |&& ) : string -> string -> string

val execute_cmd : ?mask:string list -> string -> (unit, string) result Lwt.t

val git_fetch : ?force:bool -> GitHub_types.remote_ref_info -> string -> string

val git_push :
     ?force:bool
  -> ?options:string
  -> remote_ref:GitHub_types.remote_ref_info
  -> local_ref:string
  -> unit
  -> string

val git_delete : remote_ref:GitHub_types.remote_ref_info -> string

val git_make_ancestor :
     pr_title:string
  -> pr_number:int
  -> base:string
  -> string
  -> (bool, string) result Lwt.t

val git_test_modified :
  base:string -> head:string -> string -> (bool, string) result Lwt.t

val pr_from_branch : string -> int option * string

val parse_gitlab_repo_url :
  http_repo_url:string -> (string * string, string) result

val init_git_bare_repository : bot_info:Bot_info.t -> unit Lwt.t
