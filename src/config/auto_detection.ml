open Base
open Bot_components
open GitHub_types
open Utils
open Lwt.Infix

(** Logging helper *)
let log_info fmt = Stdio.printf Stdlib.(fmt ^^ "\n%!")

let log_error fmt = Stdio.eprintf Stdlib.("ERROR: " ^^ fmt ^^ "\n%!")

(** Helper to find first matching result in a list with async operations *)
let rec find_map_s ~f = function
  | [] ->
      Lwt.return None
  | x :: xs -> (
      f x
      >>= function
      | Some result -> Lwt.return (Some result) | None -> find_map_s ~f xs )

(** Auto-detect GitLab domain by searching all configured GitLab instances *)
let auto_detect_gitlab_info ~bot_info ~github_owner ~github_repo =
  let gitlab_instances = Bot_info.gitlab_instances_keys bot_info in
  let search_term = f "%s/%s" github_owner github_repo in
  log_info "Auto-detecting GitLab for %s/%s" github_owner github_repo ;
  find_map_s
    ~f:(fun domain ->
      log_info "Searching GitLab instance: %s" domain ;
      GitLab_queries.search_projects ~bot_info ~gitlab_domain:domain
        ~search_term ()
      >>= function
      | Ok projects when not (List.is_empty projects) -> (
        (* Found matching project - use the first one *)
        match List.hd projects with
        | Some project ->
            log_info "Found GitLab project: %s/%s on %s" project.owner
              project.repo domain ;
            Lwt.return (Some (domain, project.owner, project.repo))
        | None ->
            Lwt.return None )
      | Ok _ ->
          log_info "No projects found on %s" domain ;
          Lwt.return None
      | Error error ->
          log_error "Failed to search GitLab instance %s: %s" domain error ;
          Lwt.return None )
    gitlab_instances
  >>= function
  | Some (domain, owner, repo) ->
      Lwt.return (Some (domain, owner, repo))
  | None ->
      (* Not found - use default domain with same owner/repo *)
      log_info "No GitLab project found, using default domain" ;
      Lwt.return (Some (Default.gitlab_domain, github_owner, github_repo))

(* Auto-detect organization and term from GitHub API *)
let auto_detect_org_team ~bot_info ~github_owner ~github_repo =
  let open GitHub_types in
  GitHub_queries.get_repository_info ~bot_info ~owner:github_owner
    ~repo:github_repo ()
  >>= function
  | Ok repo_info -> (
      let org_name = Some repo_info.owner in
      (* Query teams in organization *)
      GitHub_queries.get_organization_teams ~bot_info ~org:repo_info.owner ()
      >>= function
      | Ok teams when not (List.is_empty teams) ->
          (* Find common team names using exact match (more reliable) *)
          let preferred_team_names =
            ["contributors"; "maintainers"; "core"; "team"]
          in
          let team_name =
            List.find teams ~f:(fun team ->
                List.mem preferred_team_names
                  (String.lowercase team.slug)
                  ~equal:String.equal )
            |> Option.map ~f:(fun team -> team.slug)
            |> Option.value ~default:Default.team_name
          in
          log_info "Detected org: %s, team: %s" repo_info.owner team_name ;
          Lwt.return (Some (org_name, Some team_name))
      | Ok _ ->
          log_info "No teams found for org: %s" repo_info.owner ;
          Lwt.return (Some (org_name, Some Default.team_name))
      | Error err ->
          log_error "Failed to get teams for org %s: %s" repo_info.owner err ;
          (* Fallback to generic default*)
          Lwt.return (Some (org_name, Some Default.team_name)) )
  | Error err ->
      log_error "Failed to get repository info for %s/%s: %s" github_owner
        github_repo err ;
      Lwt.return None

(* Auto-detect labels from GitHub repository (optional - can be skipped if API fails) *)
let auto_detect_labels ~bot_info ~github_owner ~github_repo =
  GitHub_queries.get_all_labels ~bot_info ~owner:github_owner ~repo:github_repo
    ()
  >>= function
  | Ok label_list ->
      (* Match against common label patterns using exact or substring matching *)
      let find_label pattern =
        let normalized_pattern = String.lowercase pattern in
        List.find label_list ~f:(fun (label : label_info) ->
            let normalized = String.lowercase label.name in
            String.equal normalized normalized_pattern
            || String.is_substring normalized ~substring:normalized_pattern )
        |> Option.map ~f:(fun (label : label_info) -> label.name)
      in
      let labels =
        { Repo_config.needs_rebase= find_label "rebase"
        ; stale= find_label "stale"
        ; needs_full_ci= find_label "full"
        ; request_full_ci= find_label "request"
        ; needs_independent_fix= find_label "independent" }
      in
      log_info "Detected labels for %s/%s" github_owner github_repo ;
      Lwt.return (Some labels)
  | Error errr ->
      log_error "Failed to get labels for %s/%s: %s" github_owner github_repo
        errr ;
      Lwt.return None

(* Complete auto-detection from API with caching *)
let auto_detect_from_apis ~bot_info ~github_owner ~github_repo =
  (* Check cache first *)
  match Cache.get_cached ~owner:github_owner ~repo:github_repo with
  | Some cached ->
      log_info "Using cached auto-detection for %s/%s" github_owner github_repo ;
      Lwt.return cached
  | None ->
      log_info "Running auto-detection for %s/%s" github_owner github_repo ;
      let open Lwt.Syntax in
      (* Only detect GitLab domain and org/team - skip complex job/label
         detection for now *)
      let* gitlab_info =
        auto_detect_gitlab_info ~bot_info ~github_owner ~github_repo
      in
      let* org_team =
        auto_detect_org_team ~bot_info ~github_owner ~github_repo
      in
      let gitlab_domain, gitlab_owner, gitlab_repo =
        match gitlab_info with
        | Some (d, o, r) ->
            (Some d, Some o, Some r)
        | None ->
            (None, None, None)
      in
      let org_name, team_name =
        match org_team with Some (o, t) -> (o, t) | None -> (None, None)
      in
      (* Optionally detect labels (non-blocking) *)
      let* labels = auto_detect_labels ~bot_info ~github_owner ~github_repo in
      let detected_config =
        { Repo_config.github_owner
        ; github_repo
        ; gitlab_domain
        ; gitlab_owner
        ; gitlab_repo
        ; github_installation_id= None (* Will be detected from webhooks *)
        ; github_project_number= None
        ; org_name
        ; team_name
        ; minimizer_url= Some Default.minimizer_url
        ; ci_config= Some Default.ci_config
        ; labels
        ; jobs= None (* Skip job detection - require explicit config *)
        ; documentation= None }
      in
      (* Cache the result *)
      Cache.set_cached ~owner:github_owner ~repo:github_repo
        ~data:detected_config ;
      Lwt.return detected_config

(* TODO: GitLab CI job detection:
   - Requires proper YAML parsing (not regex)
   - Less critical than GitLab domain detection
   - Can be added later if needed
     - Users can provide explicit config for jobs
*)
