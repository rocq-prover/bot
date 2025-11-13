val gitlab_domain : string

val team_name : string

val labels : Repo_config.label_config

val ci_config : Repo_config.ci_config

val minimizer_url_from_env : unit -> string option
(** Get minimizer URL from environment variable if set, otherwise None.
    Allows setting a global default via BOT_MINIMIZER_URL environment variable. *)

val get_defaults : owner:string -> repo:string -> Repo_config.t
