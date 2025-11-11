open Base
open Bot_components
open Utils

(** Repository-spcecific CI configuration *)
type ci_config =
  { full_ci_variable: string option
  ; skip_docker_variable: string option
  ; docker_path_pattern: string option }

(** Repository-specific labels configuration *)
type label_config =
  { needs_rebase: string option
  ; stale: string option
  ; needs_full_ci: string option
  ; request_full_ci: string option
  ; needs_independent_fix: string option }

(** Repository-specific job name configuration *)
type job_config =
  { bench: string option
  ; doc_refman: string list option (* Pipe-separated string: "job1|job2" *)
  ; doc_init: string option
  ; doc_stdlib: string list option (* Pipe-separated string: "job1|job2" *)
  ; doc_ml_api: string option }

(** Repository-specific documentation paths *)
type doc_config =
  { refman_path: string option
  ; corelib_path: string option
  ; stdlib_path: string option
  ; ml_api_path: string option }

(** Complete repository configuration *)

type t =
  { github_owner: string
  ; github_repo: string
  ; gitlab_domain: string option
  ; gitlab_owner: string option
  ; gitlab_repo: string option
  ; github_installation_id: int option
  ; github_project_number: int option
  ; org_name: string option
  ; team_name: string option
  ; minimizer_url: string option
  ; ci_config: ci_config option
  ; labels: label_config option
  ; jobs: job_config option
  ; documentation: doc_config option }

(** Helper to extract a string value from a table *)
let get_string_value table key =
  try
    match Utils.find key table with Toml.Types.TString s -> Some s | _ -> None
  with
  | Stdlib.Not_found ->
      None
  | Failure msg ->
      (* TODO: handle error more gracefully*)
      failwith (f "Failed to parse string value: %s" msg)

(** Instead of TOML arrays, we use a single string to pipe separators. This is a
  workaround to handle both single string and array.

For example, instead of:
```toml
doc_refman = ["doc:refman", "doc:ci-refman"]
doc_stdlib = ["doc:stdlib", "doc:stdlib:dune"]
```
We can use:
```toml
doc_refman = "doc:refman|doc:ci-refman"
doc_stdlib = "doc:stdlib|doc:stdlib:dune"
```
*)
let parse_pipe_separated str =
  let open Base in
  String.split ~on:'|' str |> List.map ~f:String.strip
  |> List.filter ~f:(fun s -> not (String.is_empty s))

(** Parse CI configuration from TOML*)
let parse_ci_config toml_data =
  try
    match Utils.find "ci" toml_data with
    | Toml.Types.TTable ci_data ->
        Some
          { full_ci_variable= get_string_value ci_data "full_ci_variable"
          ; skip_docker_variable=
              get_string_value ci_data "skip_docker_variable"
          ; docker_path_pattern= get_string_value ci_data "docker_path_pattern"
          }
    | _ ->
        None
  with
  | Stdlib.Not_found ->
      None
  | Failure msg ->
      (* TODO: handle error more gracefully*)
      failwith (f "Failed to parse CI configuration: %s" msg)

(** Parse label configuration from TOML *)
let parse_label_config toml_data =
  try
    match Utils.find "labels" toml_data with
    | Toml.Types.TTable label_data ->
        Some
          { needs_rebase= get_string_value label_data "needs_rebase"
          ; stale= get_string_value label_data "stale"
          ; needs_full_ci= get_string_value label_data "needs_full_ci"
          ; request_full_ci= get_string_value label_data "request_full_ci"
          ; needs_independent_fix=
              get_string_value label_data "needs_independent_fix" }
    | _ ->
        None
  with
  | Stdlib.Not_found ->
      None
  | Failure msg ->
      (* TODO: handle error more gracefully*)
      failwith (f "Failed to parse label configuration: %s" msg)

(** Parse job configuration from TOML *)
let parse_job_config toml_data =
  try
    match Utils.find "jobs" toml_data with
    | Toml.Types.TTable job_data ->
        Some
          { bench= get_string_value job_data "bench"
          ; doc_refman=
              ( match get_string_value job_data "doc_refman" with
              | Some s ->
                  Some (parse_pipe_separated s)
              | None ->
                  None )
          ; doc_init= get_string_value job_data "doc_init"
          ; doc_stdlib=
              ( match get_string_value job_data "doc_stdlib" with
              | Some s ->
                  Some (parse_pipe_separated s)
              | None ->
                  None )
          ; doc_ml_api= get_string_value job_data "doc_ml_api" }
    | _ ->
        None
  with
  | Stdlib.Not_found ->
      None
  | Failure msg ->
      (* TODO: handle error more gracefully*)
      failwith (f "Failed to parse job configuration: %s" msg)

(** Parse documentation configuration from TOML *)
let parse_doc_config toml_data =
  try
    match Utils.find "documentation" toml_data with
    | Toml.Types.TTable doc_data ->
        Some
          { refman_path= get_string_value doc_data "refman_path"
          ; corelib_path= get_string_value doc_data "corelib_path"
          ; stdlib_path= get_string_value doc_data "stdlib_path"
          ; ml_api_path= get_string_value doc_data "ml_api_path" }
    | _ ->
        None
  with
  | Stdlib.Not_found ->
      None
  | Failure msg ->
      (* TODO: handle error more gracefully*)
      failwith (f "Failed to parse documentation configuration: %s" msg)

(** Parse_a single repository configuration from TOML *)
let parse_repo_config repo_key (repo_data : Toml.Types.table) =
  try
    let github_full =
      get_string_value repo_data "github"
      |> Option.value
           ~default:(f "Missing 'github' key for repository %s" repo_key)
    in
    let github_owner, github_repo =
      match Base.String.split ~on:'/' github_full with
      | [owner; repo] ->
          (owner, repo)
      | _ ->
          (* TODO: handle error more gracefully *)
          failwith
            (f
               "Invalid 'github' value in repository.%s: expected 'owner/repo' \
                format"
               repo_key )
    in
    let github_installation_id =
      get_string_value repo_data "github_installation_id"
      |> Option.map ~f:Int.of_string
    in
    let github_project_number =
      get_string_value repo_data "github_project_number"
      |> Option.map ~f:Int.of_string
    in
    Some
      { github_owner
      ; github_repo
      ; gitlab_domain= get_string_value repo_data "gitlab_domain"
      ; gitlab_owner= get_string_value repo_data "gitlab_owner"
      ; gitlab_repo= get_string_value repo_data "gitlab_repo"
      ; github_installation_id
      ; github_project_number
      ; org_name= get_string_value repo_data "org_name"
      ; team_name= get_string_value repo_data "team_name"
      ; minimizer_url= get_string_value repo_data "minimizer_url"
      ; ci_config= parse_ci_config repo_data
      ; labels= parse_label_config repo_data
      ; jobs= parse_job_config repo_data
      ; documentation= parse_doc_config repo_data }
  with
  | Stdlib.Not_found ->
      None
  | Failure msg ->
      (* TODO: handle error more gracefully*)
      failwith (f "Failed to parse repository %s: %s" repo_key msg)

(** Parse all repository configurations from TOML*)
let parse_all_repo_configs toml_data =
  let open Base in
  try
    match Utils.find "repositories" toml_data with
    | Toml.Types.TTable repos_data ->
        Utils.list_table_keys repos_data
        |> List.filter_map ~f:(fun repo_key ->
               match Utils.find repo_key repos_data with
               | Toml.Types.TTable repo_data ->
                   parse_repo_config repo_key repo_data
               | _ ->
                   None )
    | _ ->
        []
  with
  | Stdlib.Not_found ->
      []
  | Failure msg ->
      (* TODO: handle error more gracefully*)
      failwith (f "Failed to parse repository configurations: %s" msg)

(** Create a lookup table from owner/repo to configuration *)
let create_repo_config_table toml_data =
  let configs = parse_all_repo_configs toml_data in
  let table = Hashtbl.create (module String) in
  List.iter configs ~f:(fun config ->
      let key = f "%s/%s" config.github_owner config.github_repo in
      Hashtbl.set table ~key ~data:config ) ;
  table

(** Get repository configurtation by owner and repo *)
let get_repo_config ~owner ~repo repo_config_table =
  let key = f "%s/%s" owner repo in
  Hashtbl.find_exn repo_config_table key

(** Check if a repository has configurtaion in the table *)
let has_repo_config ~owner ~repo repo_config_table =
  let key = f "%s/%s" owner repo in
  Hashtbl.mem repo_config_table key
