open Base

type t =
  { gitlab_instances: (string, string * string) Hashtbl.t
  ; github_install_token: string option
  ; github_name: string
  ; email: string
  ; domain: string
  ; app_id: int
  ; api_timeout: float
        (** API timeout in seconds for GitHub/GitLab queries. Defaults to 5.0 if not set. *)
  }

(* Returns the GitHub installation token. Requires installation token to be set. *)
let github_token bot_info =
  match bot_info.github_install_token with
  | Some t ->
      t
  | None ->
      (* TODO: use Result.t later *)
      failwith
        "GitHub installation token is required. Please ensure the GitHub App \
         is installed and an installation token is available."

let gitlab_name_and_token bot_info gitlab_domain =
  match Hashtbl.find bot_info.gitlab_instances gitlab_domain with
  | Some t ->
      Ok t
  | None ->
      Error
        ( "I don't know about GitLab domain " ^ gitlab_domain
        ^ " (not in my configuration file)" )

let gitlab_token bot_info gitlab_domain =
  gitlab_name_and_token bot_info gitlab_domain |> Result.map ~f:snd

let gitlab_instances_keys bot_info = Hashtbl.keys bot_info.gitlab_instances
