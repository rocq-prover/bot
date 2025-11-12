open Base
open Cohttp_lwt_unix
open Bot_info
open Utils

let send_graphql_query ~gitlab_domain =
  GraphQL_query.send_graphql_query ~api:(GitLab gitlab_domain)

let get_build_trace ~bot_info ~gitlab_domain ~project_id ~build_id =
  let uri =
    f "https://%s/api/v4/projects/%d/jobs/%d/trace" gitlab_domain project_id
      build_id
    |> Uri.of_string
  in
  let open Lwt_result.Infix in
  gitlab_name_and_token bot_info gitlab_domain
  |> Lwt.return
  >>= fun (name, token) ->
  let gitlab_header = [("Private-Token", token)] in
  let headers = HTTP_utils.headers gitlab_header name in
  let open Lwt.Infix in
  Client.get ~headers uri
  >>= fun (_response, body) ->
  Cohttp_lwt.Body.to_string body |> Lwt.map Result.return

let get_retry_nb ~bot_info ~gitlab_domain ~full_name ~build_id ~build_name =
  let open GitLab_GraphQL.GetRetriedJobs in
  let open Lwt.Infix in
  makeVariables ~fullPath:full_name
    ~jobId:
      (build_id |> f {|"gid://gitlab/Ci::Build/%d"|} |> Yojson.Basic.from_string)
    ()
  |> serializeVariables |> variablesToJson
  |> send_graphql_query ~bot_info ~gitlab_domain ~query
       ~parse:(Fn.compose parse unsafe_fromJson)
  >|= function
  | Ok
      { project=
          Some {job= Some {pipeline= Some (`Pipeline {jobs= Some {count= 0}})}}
      } ->
      Ok 0
  | Ok
      { project=
          Some
            { job=
                Some
                  { pipeline=
                      Some (`Pipeline {jobs= Some {count; nodes= Some jobs}}) }
            } } ->
      if count > Array.length jobs then Error "Too many retried jobs"
      else
        Ok
          (Array.count jobs ~f:(function
            | Some {name= Some name} ->
                String.equal build_name name
            | None | Some {name= None} ->
                false ) )
  | Ok
      { project=
          Some
            {job= Some {pipeline= Some (`Pipeline {jobs= Some {nodes= None}})}}
      } ->
      Error "There are retried jobs but we failed to get them"
  | Ok {project= Some {job= Some {pipeline= Some (`Pipeline {jobs= None})}}} ->
      Error "Could not get the number of retried jobs"
  | Ok {project= Some {job= Some {pipeline= Some _}}} ->
      Error "Did not get the full information about the pipeline"
  | Ok {project= Some {job= Some {pipeline= None}}} ->
      Error "Could not retrieve the pipeline of the job"
  | Ok {project= Some {job= None}} ->
      Error "Could not retrieve the job"
  | Ok {project= None} ->
      Error "Could not retrieve the project"
  | Error err ->
      Error (f "Request to get retried jobs failed: %s" err)

(** Parse GraphQL response into list of project_info.
    Returns empty list if no projects found. *)
let search_projects_of_resp resp =
  let open GitLab_GraphQL.SearchProjects in
  let open GitLab_types in
  match resp.projects with
  | None ->
      Ok []
  | Some projects -> (
    match projects.nodes with
    | None ->
        Ok []
    | Some projects_array ->
        let parsed =
          projects_array |> Array.to_list |> List.filter_opt
          |> List.filter_map ~f:(fun proj ->
                 match String.split ~on:'/' proj.fullPath with
                 | owner :: repo_parts when not (List.is_empty repo_parts) ->
                     Some
                       { id= proj.id
                       ; full_path= proj.fullPath
                       ; owner
                       ; repo= String.concat ~sep:"/" repo_parts }
                 | _ ->
                     None )
        in
        Ok parsed )

(** Search projects with timeout (defaults to bot_info.api_timeout, or 5.0 seconds).
    Uses GraphQL API to find projects matching the search term.
    Returns empty list if no projects found or Error on failure. *)
let search_projects ~bot_info ~gitlab_domain ~search_term
    ?(timeout = bot_info.api_timeout) () =
  let open GitLab_GraphQL.SearchProjects in
  let open Lwt.Infix in
  let query_lwt =
    makeVariables ~search:search_term ()
    |> serializeVariables |> variablesToJson
    |> send_graphql_query ~bot_info ~gitlab_domain ~query
         ~parse:(Fn.compose parse unsafe_fromJson)
  in
  Utils.with_timeout ~timeout query_lwt
  >|= Result.map_error ~f:(fun err ->
          f "Query search_projects failed with %s" err )
  >|= Result.bind ~f:search_projects_of_resp

(** Parse GraphQL response into CI config file content.
    Returns None if config file not found. *)
let ci_config_file_of_resp ~full_path resp =
  let open GitLab_GraphQL.GetCIConfigFile in
  match resp.project with
  | None ->
      Error (f "Project %s not found." full_path)
  | Some proj -> (
    match proj.repository with
    | None ->
        Ok None
    | Some repo ->
        let blob_content =
          Option.bind repo.blobs ~f:(fun blobs_conn ->
              Option.bind blobs_conn.nodes ~f:(fun blobs ->
                  if Array.length blobs > 0 then
                    Option.bind (Array.get blobs 0) ~f:(fun blob ->
                        blob.rawBlob )
                  else None ) )
        in
        Ok blob_content )

(** Get CI config file content with timeout (defaults to bot_info.api_timeout, or 5.0 seconds).
    Searches for .gitlab-ci.yml or .gitlab-ci.yaml in the repository.
    Returns None if config file not found or Error if project doesn't exist. *)
let get_ci_config_file ~bot_info ~gitlab_domain ~full_path
    ?(timeout = bot_info.api_timeout) () =
  let open GitLab_GraphQL.GetCIConfigFile in
  let open Lwt.Infix in
  let query_lwt =
    makeVariables ~fullPath:full_path ()
    |> serializeVariables |> variablesToJson
    |> send_graphql_query ~bot_info ~gitlab_domain ~query
         ~parse:(Fn.compose parse unsafe_fromJson)
  in
  Utils.with_timeout ~timeout query_lwt
  >|= Result.map_error ~f:(fun err ->
          f "Query get_ci_config_file failed with %s" err )
  >|= Result.bind ~f:(ci_config_file_of_resp ~full_path)
