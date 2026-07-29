open Base
open Bot_info
open GitHub_types
open Lwt.Infix
open Utils

(* Parses TOML mappings between GitHub and GitLab repositories *)
let parse_mappings mappings =
  let assoc =
    Utils.list_table_keys mappings
    |> List.map ~f:(fun k ->
        match
          ( Utils.subkey_value mappings k "github"
          , Utils.subkey_value mappings k "gitlab" )
        with
        | Some gh, Some gl ->
            let gl_domain =
              Utils.subkey_value mappings k "gitlab_domain"
              |> Option.value ~default:"gitlab.com"
            in
            (gh, (gl_domain, gl))
        | _, _ ->
            failwith (f "Missing github or gitlab key for mappings.%s" k) )
  in
  let assoc_rev =
    List.map assoc ~f:(fun (gh, (gl_domain, gl)) -> (gl_domain ^ "/" ^ gl, gh))
  in
  let get_table t =
    match t with
    | `Duplicate_key _ ->
        raise (Failure "Duplicate key in config.")
    | `Ok t ->
        t
  in
  ( get_table (Hashtbl.of_alist (module String) assoc)
  , get_table (Hashtbl.of_alist (module String) assoc_rev) )

(* Constructs a GitLab repository URL with authentication token *)
let gitlab_repo ~bot_info ~gitlab_domain ~gitlab_full_name =
  gitlab_token bot_info gitlab_domain
  |> Result.map ~f:(fun token ->
      f "https://oauth2:%s@%s/%s.git" token gitlab_domain gitlab_full_name )

(* Maps a GitLab repository to its corresponding GitHub repository *)
let github_repo_of_gitlab_project_path ~gitlab_mapping ~gitlab_domain
    ~gitlab_repo_full_name =
  let full_name_with_domain = gitlab_domain ^ "/" ^ gitlab_repo_full_name in
  let github_full_name =
    match Hashtbl.find gitlab_mapping full_name_with_domain with
    | Some value ->
        value
    | None ->
        Stdio.printf
          "Warning: No correspondence found for GitLab repository %s.\n"
          full_name_with_domain ;
        gitlab_repo_full_name
  in
  match Str.split (Str.regexp "/") github_full_name with
  | [owner; repo] ->
      (owner, repo)
  | _ ->
      failwith
        (f "Could not split repository full name %s into (owner, repo)."
           github_full_name )

(* Maps a GitLab repository URL to its corresponding GitHub repository *)
let github_repo_of_gitlab_url ~gitlab_mapping ~http_repo_url =
  Git_utils.parse_gitlab_repo_url ~http_repo_url
  |> Result.map ~f:(fun (gitlab_domain, gitlab_repo_full_name) ->
      github_repo_of_gitlab_project_path ~gitlab_mapping ~gitlab_domain
        ~gitlab_repo_full_name )

(* Creates a GitLab remote reference for a GitHub PR to enable triggering GitLab CI/CD pipelines *)
let gitlab_ci_ref_for_github_pr ~bot_info ~(issue : issue) ~github_mapping
    ~gitlab_mapping =
  let default_gitlab_domain = "gitlab.com" in
  let gh_repo = issue.owner ^ "/" ^ issue.repo in
  (* First, we check our hashtable for a key named after the GitHub
     repository and return the associated GitLab repository. If the
     key is not found, we load the config file from the default branch.
     Last (backward-compatibility) we assume the GitLab and GitHub
     projects are named the same. *)
  let default_value = (default_gitlab_domain, gh_repo) in
  ( match Hashtbl.find github_mapping gh_repo with
    | None -> (
        Stdio.printf "No correspondence found for GitHub repository %s/%s.\n"
          issue.owner issue.repo ;
        GitHub_queries.get_default_branch ~bot_info ~owner:issue.owner
          ~repo:issue.repo
        >>= function
        | Ok branch -> (
            GitHub_queries.get_file_content ~bot_info ~owner:issue.owner
              ~repo:issue.repo ~branch
              ~file_name:(f "%s.toml" bot_info.github_name)
            >>= function
            | Ok (Some content) ->
                let gl_domain =
                  Option.value
                    (Utils.subkey_value
                       (Utils.toml_of_string content)
                       "mapping" "gitlab_domain" )
                    ~default:default_gitlab_domain
                in
                let gl_repo =
                  Option.value
                    (Utils.subkey_value
                       (Utils.toml_of_string content)
                       "mapping" "gitlab" )
                    ~default:gh_repo
                in
                ( match
                    Hashtbl.add gitlab_mapping
                      ~key:(gl_domain ^ "/" ^ gl_repo)
                      ~data:gh_repo
                  with
                | `Duplicate ->
                    ()
                | `Ok ->
                    () ) ;
                ( match
                    Hashtbl.add github_mapping ~key:gh_repo
                      ~data:(gl_domain, gl_repo)
                  with
                | `Duplicate ->
                    ()
                | `Ok ->
                    () ) ;
                Lwt.return (gl_domain, gl_repo)
            | _ ->
                Lwt.return default_value )
        | _ ->
            Lwt.return default_value )
    | Some r ->
        Lwt.return r )
  >|= fun (gitlab_domain, gitlab_full_name) ->
  gitlab_repo ~gitlab_domain ~gitlab_full_name ~bot_info
  |> Result.map ~f:(fun gl_repo ->
      {name= f "refs/heads/pr-%d" issue.number; repo_url= gl_repo} )

(* TODO: ensure there's no race condition for 2 push with very close timestamps *)
let mirror_action ~bot_info ?(force = true) ~gitlab_domain ~gh_owner ~gh_repo
    ~gl_owner ~gl_repo ~base_ref ~head_sha () =
  (let open Lwt_result.Infix in
   let local_ref = base_ref ^ "-" ^ head_sha in
   let gh_ref =
     {repo_url= f "https://github.com/%s/%s" gh_owner gh_repo; name= base_ref}
   in
   (* TODO: generalize to use repository mappings, with enhanced security *)
   gitlab_repo ~bot_info ~gitlab_domain
     ~gitlab_full_name:(gl_owner ^ "/" ^ gl_repo)
   |> Lwt.return
   >>= fun gl_repo ->
   let gl_ref = {repo_url= gl_repo; name= base_ref} in
   Git_utils.git_fetch gh_ref local_ref
   |> Git_utils.execute_cmd
   >>= fun () ->
   Git_utils.git_push ~force ~remote_ref:gl_ref ~local_ref ()
   |> Git_utils.execute_cmd )
  >>= function
  | Ok () ->
      Lwt.return_unit
  | Error e ->
      Lwt_io.printlf
        "Error while mirroring branch/tag %s of repository %s/%s: %s" base_ref
        gh_owner gh_repo e
