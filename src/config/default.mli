val gitlab_domain : string

val team_name : string

val labels : Repo_config.label_config

val ci_config : Repo_config.ci_config

val minimizer_url : string

val get_defaults : owner:string -> repo:string -> Repo_config.t
