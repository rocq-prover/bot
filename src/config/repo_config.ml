open Base
open Utils

type repo_jobs_config =
  { bench_job: string option
  ; bench_native_variables: (string * string) list
  ; use_rocq_job_status: bool
  ; use_rocq_ci_options: bool
  ; silence_docker_manifest_errors: bool
  ; doc_artifact_jobs: string list }

type backport_config = {github_project_number: int option}

type team_permission = {team_name: string; permission: string}

type t =
  { github_owner: string
  ; github_repo: string
  ; gitlab_domain: string option
  ; gitlab_owner: string option
  ; gitlab_repo: string option
  ; backporting: backport_config
  ; github_installation_id: int option
  ; org_name: string option
  ; alert_mention: string option
  ; teams: team_permission list
  ; minimizer_url: string option
  ; contributing_url: string option
  ; same_branch_warning: string option
  ; mergeable_base_branch: string option
  ; overlay_path_regexp: string option
  ; jobs: repo_jobs_config }

let default_jobs =
  { bench_job= None
  ; bench_native_variables= []
  ; use_rocq_job_status= false
  ; use_rocq_ci_options= false
  ; silence_docker_manifest_errors= false
  ; doc_artifact_jobs= [] }

let default_backporting = {github_project_number= None}

let parse_key_value_pair s =
  match String.lsplit2 s ~on:'=' with
  | Some (key, value) when not (String.is_empty key) ->
      Some (key, value)
  | _ ->
      None

let parse_jobs tbl key =
  match subkey_table tbl key "jobs" with
  | None ->
      default_jobs
  | Some jobs_tbl ->
      { bench_job=
          key_value jobs_tbl "bench_job"
          |> Option.bind ~f:(fun s ->
              if String.is_empty s then None else Some s )
      ; bench_native_variables=
          key_array jobs_tbl "bench_native_variables"
          |> Option.value ~default:[]
          |> List.filter_map ~f:parse_key_value_pair
      ; use_rocq_job_status=
          key_bool jobs_tbl "use_rocq_job_status" |> Option.value ~default:false
      ; use_rocq_ci_options=
          key_bool jobs_tbl "use_rocq_ci_options" |> Option.value ~default:false
      ; silence_docker_manifest_errors=
          key_bool jobs_tbl "silence_docker_manifest_errors"
          |> Option.value ~default:false
      ; doc_artifact_jobs=
          key_array jobs_tbl "doc_artifact_jobs" |> Option.value ~default:[] }

let parse_backporting tbl key =
  match subkey_table tbl key "backporting" with
  | None ->
      default_backporting
  | Some bp_tbl ->
      {github_project_number= key_int bp_tbl "github_project_number"}

let parse_teams tbl k =
  match
    Toml.Lenses.(get tbl (key k |-- table |-- key "teams" |-- array |-- tables))
  with
  | None ->
      []
  | Some team_tables ->
      List.filter_map team_tables ~f:(fun team_tbl ->
          match
            (key_value team_tbl "team_name", key_value team_tbl "permission")
          with
          | Some team_name, Some permission ->
              Some {team_name; permission}
          | _ ->
              None )

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
          ; backporting= parse_backporting tbl key
          ; github_installation_id= subkey_int tbl key "github_installation_id"
          ; org_name= subkey_value tbl key "org_name"
          ; alert_mention= subkey_value tbl key "alert_mention"
          ; teams= parse_teams tbl key
          ; minimizer_url= subkey_value tbl key "minimizer_url"
          ; contributing_url= subkey_value tbl key "contributing_url"
          ; same_branch_warning= subkey_value tbl key "same_branch_warning"
          ; mergeable_base_branch= subkey_value tbl key "mergeable_base_branch"
          ; overlay_path_regexp= subkey_value tbl key "overlay_path_regexp"
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

let project_organization cfg =
  Option.value cfg.org_name ~default:cfg.github_owner

let backport_enabled cfg = Option.is_some cfg.backporting.github_project_number

let find_by_backport_project ~install_id ~project_number tbl =
  Hashtbl.to_alist tbl
  |> List.find_map ~f:(fun (_key, cfg) ->
      match
        (cfg.github_installation_id, cfg.backporting.github_project_number)
      with
      | Some iid, Some pn
        when Int.equal iid install_id && Int.equal pn project_number ->
          Some cfg
      | _ ->
          None )

let is_bench_job cfg build_name =
  match cfg.jobs.bench_job with
  | Some name ->
      String.equal name build_name
  | None ->
      false

let bench_native_enabled cfg =
  not (List.is_empty cfg.jobs.bench_native_variables)

let is_doc_artifact_job cfg build_name =
  List.mem cfg.jobs.doc_artifact_jobs build_name ~equal:String.equal

let github_full_name cfg = cfg.github_owner ^ "/" ^ cfg.github_repo

let gitlab_job_url cfg ~job_id =
  match (cfg.gitlab_domain, cfg.gitlab_owner, cfg.gitlab_repo) with
  | Some domain, Some owner, Some repo ->
      Some (f "https://%s/%s/%s/-/jobs/%d" domain owner repo job_id)
  | _ ->
      None

let gitlab_pages_host domain owner =
  if String.equal domain "gitlab.com" then owner ^ ".gitlab.io"
  else if String.is_prefix domain ~prefix:"gitlab." then
    owner ^ ".gitlabpages." ^ String.drop_prefix domain 7
  else owner ^ ".gitlabpages." ^ domain

let gitlab_pages_artifact_url cfg ~job_id ~artifact =
  match (cfg.gitlab_domain, cfg.gitlab_owner, cfg.gitlab_repo) with
  | Some domain, Some owner, Some repo ->
      Some
        (f "https://%s/-/%s/-/jobs/%d/artifacts/%s"
           (gitlab_pages_host domain owner)
           repo job_id artifact )
  | _ ->
      None

let team_for_permission cfg permission =
  List.find_map cfg.teams ~f:(fun t ->
      if String.equal t.permission permission then Some t.team_name else None )

let team_mention cfg ~permission =
  match team_for_permission cfg permission with
  | None ->
      None
  | Some team ->
      Some (f "@%s/%s" (project_organization cfg) team)

let should_warn_same_branch_name cfg ~same_branch_name ~opened =
  opened && same_branch_name && Option.is_some cfg.same_branch_warning

let format_same_branch_warning cfg ~base_branch =
  match cfg.same_branch_warning with
  | None ->
      None
  | Some template ->
      let contributing_url = Option.value cfg.contributing_url ~default:"" in
      Some
        ( template
        |> String.substr_replace_all ~pattern:"{base_branch}" ~with_:base_branch
        |> String.substr_replace_all ~pattern:"{contributing_url}"
             ~with_:contributing_url
        |> String.strip )
