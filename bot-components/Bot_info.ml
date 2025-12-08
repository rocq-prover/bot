open Base

type t =
  { gitlab_instances: (string, string * string) Hashtbl.t
  ; github_pat: string option
  ; github_install_token: string
  ; github_name: string
  ; email: string
  ; domain: string
  ; app_id: int }

let github_pat bot_info =
  match bot_info.github_pat with
  | Some pat ->
      pat
  | None ->
      failwith
        "No GitHub PAT available. This operation requires a GitHub PAT. Please \
         ensure the PAT is set in the configuration."

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
