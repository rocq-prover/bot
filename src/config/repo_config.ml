open Base
open Utils

type repo_jobs_config =
  {bench: string option; custom_job_status: bool; doc_jobs: string list}

type t =
  { github_owner: string
  ; github_repo: string
  ; gitlab_domain: string option
  ; gitlab_owner: string option
  ; gitlab_repo: string option
  ; github_project_number: int option
  ; github_installation_id: int option
  ; org_name: string option
  ; team_name: string option
  ; pushers_team: string option
  ; maintainers_team: string option
  ; minimizer_url: string option
  ; jobs: repo_jobs_config }

let default_jobs = {bench= None; custom_job_status= false; doc_jobs= []}

let parse_jobs tbl key =
  match subkey_table tbl key "jobs" with
  | None ->
      default_jobs
  | Some jobs_tbl ->
      { bench=
          key_value jobs_tbl "bench"
          |> Option.bind ~f:(fun s ->
              if String.is_empty s then None else Some s )
      ; custom_job_status=
          key_bool jobs_tbl "custom_job_status" |> Option.value ~default:false
      ; doc_jobs= key_array jobs_tbl "doc_jobs" |> Option.value ~default:[] }

let parse_one tbl key =
  match subkey_value tbl key "github" with
  | None ->
      failwith (f "repositories.%s: missing required 'github' key" key)
  | Some github -> (
      let parts = String.split ~on:'/' github in
      match parts with
      | [owner; repo] ->
          { github_owner= owner
          ; github_repo= repo
          ; gitlab_domain= subkey_value tbl key "gitlab_domain"
          ; gitlab_owner= subkey_value tbl key "gitlab_owner"
          ; gitlab_repo= subkey_value tbl key "gitlab_repo"
          ; github_project_number= subkey_int tbl key "github_project_number"
          ; github_installation_id= subkey_int tbl key "github_installation_id"
          ; org_name= subkey_value tbl key "org_name"
          ; team_name= subkey_value tbl key "team_name"
          ; pushers_team= subkey_value tbl key "pushers_team"
          ; maintainers_team= subkey_value tbl key "maintainers_team"
          ; minimizer_url= subkey_value tbl key "minimizer_url"
          ; jobs= parse_jobs tbl key }
      | _ ->
          failwith
            (f "repositories.%s: 'github' must be 'owner/repo', got '%s'" key
               github ) )

let make_repo_config_table toml_data =
  ( try
      match find "repositories" toml_data with
      | Toml.Types.TTable a ->
          list_table_keys a |> List.map ~f:(fun k -> (k, parse_one a k))
      | _ ->
          failwith "Invalid repositories configuration: not a table."
    with Stdlib.Not_found -> [] )
  |> Hashtbl.of_alist_exn (module String)

let find_by_github ~owner ~repo tbl =
  Hashtbl.to_alist tbl
  |> List.find_map ~f:(fun (_key, cfg) ->
      if
        String.equal cfg.github_owner owner && String.equal cfg.github_repo repo
      then Some cfg
      else None )
