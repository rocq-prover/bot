# Complete Implementation Guide: Generic Bot with API-Based Auto-Detection

## Overview

This guide provides detailed implementation steps to transform the bot from Rocq-specific to a fully generic system with API-based auto-detection. **Rocq becomes just a configured instance** with specific values, not special code.

### Design Principles

1. **No Hardcoded Patterns**: All detection via APIs or generic defaults
2. **Optimize Existing Code**: Reuse existing functions in `bot-components/` and `src/`
3. **No Duplicate Code**: Leverage what's already implemented
4. **Progressive Enhancement**: Build on existing infrastructure
5. **Performance First**: Cache API results, handle rate limits, add timeouts
6. **Graceful Degradation**: Handle API failures without crashing

### Critical Considerations

**API Rate Limits**: GitHub (5,000/hour) and GitLab (2,000-10,000/hour) have rate limits. We must:
- Cache auto-detection results per repository
- Only auto-detect when config is missing
- Add timeouts to all API calls (5 seconds default)
- Handle rate limit errors gracefully

**Error Handling**: APIs can fail. We must:
- Return `None` on failure, not crash
- Log all failures for debugging
- Use defaults when auto-detection fails
- Support partial detection (some fields succeed, others fail)

**Performance**: Auto-detection should be:
- Lazy (only when needed)
- Cached (avoid duplicate API calls)
- Asynchronous (don't block webhook processing)

### Implementation Order

**Follow phases sequentially** - each phase includes implementation AND tests. Complete one phase before moving to the next.

---

## Part 0: Project Structure & Analysis

### Final Directory Structure

```
bot/
├── bot-components/              # Shared bot components (unchanged)
│   ├── GitHub_queries.ml[i]     # Extended with new API functions
│   ├── GitLab_queries.ml[i]     # Extended with new API functions
│   ├── GitHub_GraphQL.ml        # Extended with new GraphQL queries
│   ├── GitLab_GraphQL.ml        # Extended with new GraphQL queries
│   └── ...                      # Other existing modules
│
├── src/                         # Main bot source code
│   ├── actions/                 # Action handlers (refactored to be generic)
│   ├── ci/                      # CI-related modules
│   ├── config/                  # Configuration system (NEW modules added)
│   │   ├── defaults.ml          # NEW: Generic defaults
│   │   ├── auto_detection.ml    # NEW: API-based auto-detection (with caching)
│   │   ├── config_resolver.ml   # NEW: Config merge logic
│   │   └── cache.ml             # NEW: Caching layer for auto-detection
│   ├── webhooks/                # Webhook handlers (refactored)
│   └── utils/                   # Utilities (unchanged)
│
└── tests/                       # Test suite (extended)
    ├── defaults_test.ml         # NEW
    ├── auto_detection_test.ml   # NEW
    ├── config_resolver_test.ml  # NEW
    ├── cache_test.ml            # NEW
    └── ...                       # Existing tests
```

### Existing Code to Reuse

#### GitHub APIs (Already Implemented)
```ocaml
✅ get_team_membership ~bot_info ~org ~team ~user
✅ get_default_branch ~bot_info ~owner ~repo  
✅ get_file_content ~bot_info ~owner ~repo ~branch ~file_name
✅ get_label ~bot_info ~owner ~repo ~label
✅ get_pull_request_labels ~bot_info ~owner ~repo ~pr_number
✅ get_repository_id ~bot_info ~owner ~repo
```

#### GitLab APIs (Already Implemented)
```ocaml
✅ get_build_trace ~bot_info ~gitlab_domain ~project_id ~build_id
✅ get_retry_nb ~bot_info ~gitlab_domain ~full_name ~build_id ~build_name
```

#### Webhook Structure (Already Implemented)
```ocaml
✅ Installation ID already extracted from webhooks
✅ Push events already structured with owner, repo, install_id
```

### Hardcoded Checks to Remove

Files with hardcoded `"rocq-prover"` checks:
1. **src/webhooks/github.ml** (lines 289-291, 323-326)
2. **src/actions/backport.ml** (line 20)
3. **src/actions/job.ml** (lines 47-49, 69)
4. **src/actions/pr_sync.ml** (lines 81-82, 99-102)
5. **src/ci/documentation.ml** (lines 14-21, 36-42, 179-195)

---

## Part 1: Phase-by-Phase Implementation

### Phase 1: Add Missing API Query Functions

**Goal**: Extend existing API functions to support auto-detection with proper error handling and timeouts.

#### Step 1.1: Extend GitHub GraphQL Queries

**File**: `bot-components/GitHub_GraphQL.ml`

Add new GraphQL queries:

```ocaml
(* Query to get repository information including owner details *)
(* Note: owner is a union type (Organization | User), so we need inline fragments *)
module GetRepositoryInfo =
  [%graphql
  {|
query getRepoInfo($owner: String!, $repo: String!) {
  repository(owner: $owner, name: $repo) {
    id
    owner {
      ... on Organization {
        login
        name
      }
      ... on User {
        login
      }
    }
    defaultBranchRef {
      name
    }
  }
}
|}]

(* Query to get organization teams *)
module GetOrganizationTeams =
  [%graphql
  {|
query getOrgTeams($org: String!, $first: Int = 100) {
  organization(login: $org) {
    teams(first: $first) {
      nodes {
        name
        slug
      }
    }
  }
}
|}]

(* Query to get all repository labels *)
module GetRepositoryLabels =
  [%graphql
  {|
query getRepoLabels($owner: String!, $repo: String!, $first: Int = 100) {
  repository(owner: $owner, name: $repo) {
    labels(first: $first) {
      nodes {
        id
        name
      }
    }
  }
}
|}]
```

#### Step 1.2: Add GitHub Query Functions with Timeouts

**File**: `bot-components/GitHub_queries.mli`

Add:

```ocaml
type repository_info =
  { id: GitHub_ID.t
  ; owner_login: string
  ; default_branch: string }

type team_info = { name: string; slug: string }

type label_info = { id: GitHub_ID.t; name: string }

(** Get repository info with timeout (default 5 seconds) *)
val get_repository_info :
     ?timeout:float
  -> bot_info:Bot_info.t
  -> owner:string
  -> repo:string
  -> (repository_info, string) result Lwt.t

(** Get organization teams with timeout *)
val get_organization_teams :
     ?timeout:float
  -> bot_info:Bot_info.t
  -> org:string
  -> (team_info list, string) result Lwt.t

(** Get all repository labels with timeout *)
val get_all_labels :
     ?timeout:float
  -> bot_info:Bot_info.t
  -> owner:string
  -> repo:string
  -> (label_info list, string) result Lwt.t
```

**File**: `bot-components/GitHub_queries.ml`

Add implementations with timeout handling:

```ocaml
(** Helper to add timeout to Lwt operations *)
let with_timeout ~timeout f =
  Lwt.pick
    [ f
    ; (Lwt_unix.sleep timeout >>= fun () ->
        Lwt.fail (Failure (f "Operation timed out after %.1f seconds" timeout))) ]

let get_repository_info ?(timeout = 5.0) ~bot_info ~owner ~repo =
  let open GitHub_GraphQL.GetRepositoryInfo in
  let query_fun () =
    makeVariables ~owner ~repo ()
    |> serializeVariables |> variablesToJson
    |> send_graphql_query ~bot_info ~query
         ~parse:(Fn.compose parse unsafe_fromJson)
  in
  with_timeout ~timeout query_fun
  >|= function
  | Ok result -> (
    match result.repository with
    | Some repo -> (
      match repo.defaultBranchRef with
      | Some branch ->
          Ok
            { id= GitHub_ID.of_string repo.id
            ; owner_login= repo.owner.login
            ; default_branch= branch.name }
      | None ->
          Error (f "Repository %s/%s has no default branch." owner repo) )
    | None ->
        Error (f "Repository %s/%s does not exist." owner repo) )
  | Error err ->
      Error err
  | exception Failure msg ->
      Error (f "Timeout or error: %s" msg)

let get_organization_teams ?(timeout = 5.0) ~bot_info ~org =
  let open GitHub_GraphQL.GetOrganizationTeams in
  let query_fun () =
    makeVariables ~org ()
    |> serializeVariables |> variablesToJson
    |> send_graphql_query ~bot_info ~query
         ~parse:(Fn.compose parse unsafe_fromJson)
  in
  with_timeout ~timeout query_fun
  >|= function
  | Ok result -> (
    match result.organization with
    | Some org -> (
      match org.teams.nodes with
      | Some teams ->
          Ok
            (teams |> Array.to_list |> List.filter_opt
            |> List.map ~f:(fun team -> {name= team.name; slug= team.slug}) )
      | None ->
          Ok [] )
    | None ->
        Error (f "Organization %s does not exist." org) )
  | Error err ->
      Error err
  | exception Failure msg ->
      Error (f "Timeout or error: %s" msg)

let get_all_labels ?(timeout = 5.0) ~bot_info ~owner ~repo =
  let open GitHub_GraphQL.GetRepositoryLabels in
  let query_fun () =
    makeVariables ~owner ~repo ()
    |> serializeVariables |> variablesToJson
    |> send_graphql_query ~bot_info ~query
         ~parse:(Fn.compose parse unsafe_fromJson)
  in
  with_timeout ~timeout query_fun
  >|= function
  | Ok result -> (
    match result.repository with
    | Some repo -> (
      match repo.labels.nodes with
      | Some labels ->
          Ok
            (labels |> Array.to_list |> List.filter_opt
            |> List.map ~f:(fun label ->
                   {id= GitHub_ID.of_string label.id; name= label.name} ) )
      | None ->
          Ok [] )
    | None ->
        Error (f "Repository %s/%s does not exist." owner repo) )
  | Error err ->
      Error err
  | exception Failure msg ->
      Error (f "Timeout or error: %s" msg)
```

#### Step 1.3: Add GitLab Query Functions

**File**: `bot-components/GitLab_GraphQL.ml`

Add:

```ocaml
module SearchProjects =
  [%graphql
  {|
query searchProjects($search: String!) {
  projects(search: $search, first: 10) {
    nodes {
      id
      fullPath
      namespace {
        fullPath
      }
      path
    }
  }
}
|}]

module GetCIConfigFile =
  [%graphql
  {|
query getCIConfig($fullPath: ID!) {
  project(fullPath: $fullPath) {
    repository {
      blobs(paths: [".gitlab-ci.yml", ".gitlab-ci.yaml"]) {
        nodes {
          rawBlob
          path
        }
      }
    }
  }
}
|}]
```

**File**: `bot-components/GitLab_queries.mli`

Add:

```ocaml
type project_info = { id: string; full_path: string; owner: string; repo: string }

(** Search projects with timeout *)
val search_projects :
     ?timeout:float
  -> bot_info:Bot_info.t
  -> gitlab_domain:string
  -> search_term:string
  -> (project_info list, string) result Lwt.t

(** Get CI config file with timeout *)
val get_ci_config_file :
     ?timeout:float
  -> bot_info:Bot_info.t
  -> gitlab_domain:string
  -> full_path:string
  -> (string option, string) result Lwt.t
```

**File**: `bot-components/GitLab_queries.ml`

Add implementations with timeout:

```ocaml
let search_projects ?(timeout = 5.0) ~bot_info ~gitlab_domain ~search_term =
  let open GitLab_GraphQL.SearchProjects in
  let open Lwt.Infix in
  let query_fun () =
    makeVariables ~search:search_term ()
    |> serializeVariables |> variablesToJson
    |> send_graphql_query ~bot_info ~gitlab_domain ~query
         ~parse:(Fn.compose parse unsafe_fromJson)
  in
  with_timeout ~timeout query_fun
  >|= function
  | Ok result -> (
    match result.projects.nodes with
    | Some projects ->
        let parsed =
          projects |> Array.to_list |> List.filter_opt
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
        Ok parsed
    | None ->
        Ok [] )
  | Error err ->
      Error err
  | exception Failure msg ->
      Error (f "Timeout or error: %s" msg)

let get_ci_config_file ?(timeout = 5.0) ~bot_info ~gitlab_domain ~full_path =
  let open GitLab_GraphQL.GetCIConfigFile in
  let open Lwt.Infix in
  let query_fun () =
    makeVariables ~fullPath:full_path ()
    |> serializeVariables |> variablesToJson
    |> send_graphql_query ~bot_info ~gitlab_domain ~query
         ~parse:(Fn.compose parse unsafe_fromJson)
  in
  with_timeout ~timeout query_fun
  >|= function
  | Ok result -> (
    match result.project with
    | Some proj -> (
      match proj.repository with
      | Some repo -> (
        match repo.blobs.nodes with
        | Some blobs when Array.length blobs > 0 -> (
          match Array.get blobs 0 with
          | Some blob ->
              Ok (Some blob.rawBlob)
          | None ->
              Ok None )
        | _ ->
            Ok None )
      | None ->
          Ok None )
    | None ->
        Error (f "Project %s not found." full_path) )
  | Error err ->
      Error err
  | exception Failure msg ->
      Error (f "Timeout or error: %s" msg)
```

#### Step 1.4: Test API Functions

**Verification**:
```bash
# Compile to check for errors
dune build bot-components

# Test manually or add unit tests
```

**Checklist**:
- [ ] GraphQL queries compile
- [ ] Function signatures match
- [ ] No compilation errors
- [ ] Timeout handling works

---

### Phase 2: Create Defaults Module

**Goal**: Create generic defaults that work for any repository.

#### Step 2.1: Create Defaults Module

**File**: `src/config/defaults.ml` (NEW)

```ocaml
open Base
open Utils

(** Generic defaults that work for any repository - NO repo-specific patterns *)

let gitlab_domain = "gitlab.com"

let team_name = "maintainers"

let labels =
  { Repo_config.needs_rebase= Some "needs: rebase"
  ; stale= Some "stale"
  ; needs_full_ci= Some "needs: full CI"
  ; request_full_ci= Some "request: full CI"
  ; needs_independent_fix= Some "needs: independent fix" }

let ci_config =
  { Repo_config.full_ci_variable= Some "FULL_CI"
  ; skip_docker_variable= Some "SKIP_DOCKER"
  ; docker_path_pattern= Some ".*Dockerfile.*" }

let minimizer_url =
  "https://github.com/rocq-community/run-coq-bug-minimizer/actions"

(** Get default configuration for any repository *)
let get_defaults ~owner ~repo =
  { Repo_config.github_owner= owner
  ; github_repo= repo
  ; gitlab_domain= Some gitlab_domain
  ; gitlab_owner= Some owner
  ; gitlab_repo= Some repo
  ; github_installation_id= None
  ; github_project_number= None
  ; org_name= Some owner
  ; team_name= Some team_name
  ; minimizer_url= Some minimizer_url
  ; ci_config= Some ci_config
  ; labels= Some labels
  ; jobs= None
  ; documentation= None }
```

**File**: `src/config/defaults.mli` (NEW)

```ocaml
(** Generic default configuration values for any repository *)

val get_defaults : owner:string -> repo:string -> Repo_config.t
```

#### Step 2.2: Test Defaults Module

**File**: `tests/defaults_test.ml` (NEW)

```ocaml
open Base
open Repo_config
open Defaults
open Alcotest

let test_defaults_for_any_repo () =
  let owner = "test-org" in
  let repo = "test-repo" in
  let defaults = get_defaults ~owner ~repo in
  
  (* Verify basic fields *)
  check string "github_owner" defaults.github_owner owner ;
  check string "github_repo" defaults.github_repo repo ;
  
  (* Verify generic defaults (no repo-specific patterns) *)
  check (option string) "gitlab_domain" defaults.gitlab_domain
    (Some "gitlab.com") ;
  check (option string) "org_name" defaults.org_name (Some owner) ;
  check (option string) "team_name" defaults.team_name (Some "maintainers") ;
  
  (* Verify CI config defaults *)
  ( match defaults.ci_config with
  | Some ci ->
      check (option string) "full_ci_variable" ci.full_ci_variable
        (Some "FULL_CI") ;
      check (option string) "skip_docker_variable" ci.skip_docker_variable
        (Some "SKIP_DOCKER")
  | None ->
      fail "Expected CI config defaults" ) ;
  
  (* Verify labels defaults *)
  ( match defaults.labels with
  | Some labels ->
      check (option string) "needs_rebase" labels.needs_rebase
        (Some "needs: rebase") ;
      check (option string) "stale" labels.stale (Some "stale")
  | None ->
      fail "Expected labels defaults" )

let test_defaults_no_hardcoded_patterns () =
  (* Test that defaults work for any repository name *)
  let repos = ["rocq-prover/rocq"; "coq/coq"; "math-comp/math-comp"; "ocaml/opam"] in
  List.iter repos ~f:(fun repo_full ->
      match String.split ~on:'/' repo_full with
      | [owner; repo] ->
          let defaults = get_defaults ~owner ~repo in
          check string "owner matches" defaults.github_owner owner ;
          check string "repo matches" defaults.github_repo repo ;
          (* No hardcoded checks - all repos get same generic defaults *)
          check (option string) "gitlab_domain is generic"
            defaults.gitlab_domain (Some "gitlab.com")
      | _ ->
          fail (f "Invalid repo format: %s" repo_full) )

let () =
  run "Defaults"
    [ ( "defaults"
      , [ test_case "defaults for any repo" `Quick test_defaults_for_any_repo
        ; test_case "no hardcoded patterns" `Quick
            test_defaults_no_hardcoded_patterns ] ) ]
```

**Update**: `tests/dune`

```lisp
(test
 (name defaults_test)
 (libraries base bot-components config alcotest)
 (modules defaults_test))
```

**Run Tests**:
```bash
dune exec tests/defaults_test.exe
```

**Checklist**:
- [ ] Defaults module compiles
- [ ] Tests pass
- [ ] Defaults work for any repo name
- [ ] No hardcoded patterns

---

### Phase 2.5: Create Caching Layer

**Goal**: Add caching for auto-detection results to avoid rate limits and improve performance.

#### Step 2.5.1: Create Cache Module

**File**: `src/config/cache.ml` (NEW)

```ocaml
open Base
open Utils

(** Cache entry with timestamp for TTL *)
type 'a cache_entry = { data: 'a; timestamp: float }

(** Cache TTL: 1 hour (3600 seconds) *)
let cache_ttl = 3600.0

(** In-memory cache: "owner/repo" -> (detected_config, timestamp) *)
let auto_detection_cache : (string, Repo_config.t cache_entry) Hashtbl.t =
  Hashtbl.create (module String)

(** Check if cache entry is still valid *)
let is_valid entry =
  let age = Unix.time () -. entry.timestamp in
  age < cache_ttl

(** Get cached auto-detection result *)
let get_cached ~owner ~repo =
  let key = f "%s/%s" owner repo in
  match Hashtbl.find auto_detection_cache key with
  | Some entry when is_valid entry ->
      Some entry.data
  | Some _ | None ->
      None

(** Store auto-detection result in cache *)
let set_cached ~owner ~repo ~data =
  let key = f "%s/%s" owner repo in
  let entry = { data; timestamp= Unix.time () } in
  Hashtbl.set auto_detection_cache ~key ~data:entry

(** Clear expired entries from cache *)
let cleanup_expired () =
  let now = Unix.time () in
  Hashtbl.filter_inplace auto_detection_cache ~f:(fun entry ->
      (now -. entry.timestamp) < cache_ttl )

(** Clear all cache entries *)
let clear_all () = Hashtbl.clear auto_detection_cache
```

**File**: `src/config/cache.mli` (NEW)

```ocaml
(** Caching layer for auto-detection results *)

val get_cached : owner:string -> repo:string -> Repo_config.t option
val set_cached : owner:string -> repo:string -> data:Repo_config.t -> unit
val cleanup_expired : unit -> unit
val clear_all : unit -> unit
```

#### Step 2.5.2: Test Cache Module

**File**: `tests/cache_test.ml` (NEW)

```ocaml
open Base
open Repo_config
open Cache
open Alcotest
open Bot_components.Utils

(** Helper to create a test config *)
let create_test_config ~owner ~repo ~gitlab_domain =
    { Repo_config.github_owner= owner
    ; github_repo= repo
  ; gitlab_domain= Some gitlab_domain
    ; gitlab_owner= Some owner
    ; gitlab_repo= Some repo
    ; github_installation_id= None
    ; github_project_number= None
    ; org_name= Some owner
    ; team_name= Some "maintainers"
    ; minimizer_url= None
    ; ci_config= None
    ; labels= None
    ; jobs= None
    ; documentation= None }

(** Test basic cache get/set operations *)
let test_cache_basic_operations () =
  clear_all () ;
  let owner = "test-org" in
  let repo = "test-repo" in
  let config = create_test_config ~owner ~repo ~gitlab_domain:"gitlab.com" in
  
  (* Cache miss: no entry initially *)
  check (option Repo_config.t) "cache miss initially" (get_cached ~owner ~repo) None ;
  
  (* Set cache *)
  set_cached ~owner ~repo ~data:config ;
  
  (* Cache hit: should retrieve cached value *)
  match get_cached ~owner ~repo with
  | Some cached ->
      check string "cached owner matches" cached.github_owner owner ;
      check string "cached repo matches" cached.github_repo repo ;
      check (option string) "cached gitlab_domain matches" cached.gitlab_domain
        (Some "gitlab.com") ;
      check (option string) "cached org_name matches" cached.org_name (Some owner)
  | None ->
      fail "Expected cache hit but got cache miss"

(** Test cache isolation: different repos don't interfere *)
let test_cache_isolation () =
  clear_all () ;
  let config1 = create_test_config ~owner:"org1" ~repo:"repo1" ~gitlab_domain:"gitlab.com" in
  let config2 = create_test_config ~owner:"org2" ~repo:"repo2" ~gitlab_domain:"gitlab.inria.fr" in
  
  (* Cache both repos *)
  set_cached ~owner:"org1" ~repo:"repo1" ~data:config1 ;
  set_cached ~owner:"org2" ~repo:"repo2" ~data:config2 ;
  
  (* Verify each repo has its own cached config *)
  ( match get_cached ~owner:"org1" ~repo:"repo1" with
  | Some cached ->
      check string "org1/repo1 owner" cached.github_owner "org1" ;
      check (option string) "org1/repo1 gitlab_domain" cached.gitlab_domain
        (Some "gitlab.com")
  | None ->
      fail "org1/repo1 should be cached" ) ;
  
  ( match get_cached ~owner:"org2" ~repo:"repo2" with
  | Some cached ->
      check string "org2/repo2 owner" cached.github_owner "org2" ;
      check (option string) "org2/repo2 gitlab_domain" cached.gitlab_domain
        (Some "gitlab.inria.fr")
  | None ->
      fail "org2/repo2 should be cached" ) ;
  
  (* Verify cache miss for non-existent repo *)
  check (option Repo_config.t) "non-existent repo cache miss"
    (get_cached ~owner:"nonexistent" ~repo:"repo")
    None

(** Test cache expiration: entries expire after TTL *)
let test_cache_expiration () =
  clear_all () ;
  let owner = "expire-test-org" in
  let repo = "expire-test-repo" in
  let config = create_test_config ~owner ~repo ~gitlab_domain:"gitlab.com" in
  
  (* Set cache *)
  set_cached ~owner ~repo ~data:config ;
  
  (* Immediately after setting, should be valid (cache hit) *)
  check bool "cache valid immediately after set"
    (Option.is_some (get_cached ~owner ~repo))
    true ;
  
  let now = Unix.time () in
  
  (* Test 1: Set cache with expired timestamp (older than TTL) *)
  let expired_timestamp = now -. 3700.0 in (* 3700 seconds = more than 1 hour *)
  set_cached_with_timestamp ~owner ~repo ~data:config ~timestamp:expired_timestamp ;
  
  (* Expired entry should not be returned (cache miss) *)
  check (option repo_config_testable) "expired entry returns None"
    (get_cached ~owner ~repo)
    None ;
  
  (* Test 2: Set cache with recent timestamp (within TTL) *)
  let recent_timestamp = now -. 1800.0 in (* 1800 seconds = 30 minutes, less than 1 hour *)
  set_cached_with_timestamp ~owner ~repo ~data:config ~timestamp:recent_timestamp ;
  
  (* Recent entry should be returned (cache hit) *)
  check bool "recent entry is valid (cache hit)"
    (Option.is_some (get_cached ~owner ~repo))
    true ;
  
  (* Test 3: Set cache with timestamp exactly at TTL boundary *)
  let boundary_timestamp = now -. 3600.0 in (* Exactly 1 hour ago *)
  set_cached_with_timestamp ~owner ~repo ~data:config ~timestamp:boundary_timestamp ;
  
  (* Entry at boundary should be expired (age >= TTL, so not valid) *)
  check (option repo_config_testable) "entry at TTL boundary is expired"
    (get_cached ~owner ~repo)
    None ;
  
  (* Test 4: Set cache with timestamp just before TTL *)
  let just_valid_timestamp = now -. 3599.0 in (* 1 second before TTL *)
  set_cached_with_timestamp ~owner ~repo ~data:config ~timestamp:just_valid_timestamp ;
  
  (* Entry just before boundary should be valid *)
  check bool "entry just before TTL boundary is valid"
    (Option.is_some (get_cached ~owner ~repo))
    true

(** Test cache update: setting new value overwrites old *)
let test_cache_update () =
  clear_all () ;
  let owner = "update-test-org" in
  let repo = "update-test-repo" in
  let config1 = create_test_config ~owner ~repo ~gitlab_domain:"gitlab.com" in
  let config2 = create_test_config ~owner ~repo ~gitlab_domain:"gitlab.inria.fr" in
  
  (* Set initial cache *)
  set_cached ~owner ~repo ~data:config1 ;
  
  (* Verify initial value *)
  ( match get_cached ~owner ~repo with
  | Some cached ->
      check (option string) "initial gitlab_domain" cached.gitlab_domain
        (Some "gitlab.com")
  | None ->
      fail "Expected cached value" ) ;
  
  (* Update cache with new value *)
  set_cached ~owner ~repo ~data:config2 ;
  
  (* Verify updated value *)
  ( match get_cached ~owner ~repo with
  | Some cached ->
      check (option string) "updated gitlab_domain" cached.gitlab_domain
        (Some "gitlab.inria.fr")
  | None ->
      fail "Expected updated cached value" )

(** Test cleanup_expired: removes expired entries *)
let test_cache_cleanup () =
  clear_all () ;
  let owner1 = "cleanup-org1" in
  let repo1 = "cleanup-repo1" in
  let owner2 = "cleanup-org2" in
  let repo2 = "cleanup-repo2" in
  
  let config1 = create_test_config ~owner:owner1 ~repo:repo1 ~gitlab_domain:"gitlab.com" in
  let config2 = create_test_config ~owner:owner2 ~repo:repo2 ~gitlab_domain:"gitlab.com" in
  
  (* Cache both repos *)
  set_cached ~owner:owner1 ~repo:repo1 ~data:config1 ;
  set_cached ~owner:owner2 ~repo:repo2 ~data:config2 ;
  
  (* Verify both are cached *)
  check bool "both repos cached before cleanup"
    (Option.is_some (get_cached ~owner:owner1 ~repo:repo1)
     && Option.is_some (get_cached ~owner:owner2 ~repo:repo2))
    true ;
  
  (* Run cleanup (should keep valid entries, remove expired ones) *)
  cleanup_expired () ;
  
  (* Both should still be valid (recently set) *)
  check bool "both repos still cached after cleanup (recent entries)"
    (Option.is_some (get_cached ~owner:owner1 ~repo:repo1)
     && Option.is_some (get_cached ~owner:owner2 ~repo:repo2))
    true

(** Test clear_all: removes all cache entries *)
let test_cache_clear_all () =
  clear_all () ;
  let owner1 = "clear-org1" in
  let repo1 = "clear-repo1" in
  let owner2 = "clear-org2" in
  let repo2 = "clear-repo2" in
  
  let config1 = create_test_config ~owner:owner1 ~repo:repo1 ~gitlab_domain:"gitlab.com" in
  let config2 = create_test_config ~owner:owner2 ~repo:repo2 ~gitlab_domain:"gitlab.com" in
  
  (* Cache both repos *)
  set_cached ~owner:owner1 ~repo:repo1 ~data:config1 ;
  set_cached ~owner:owner2 ~repo:repo2 ~data:config2 ;
  
  (* Verify both are cached *)
  check bool "both repos cached before clear"
    (Option.is_some (get_cached ~owner:owner1 ~repo:repo1)
     && Option.is_some (get_cached ~owner:owner2 ~repo:repo2))
    true ;
  
  (* Clear all cache *)
  clear_all () ;
  
  (* Verify both are now cache misses *)
  check bool "both repos cleared after clear_all"
    (Option.is_none (get_cached ~owner:owner1 ~repo:repo1)
     && Option.is_none (get_cached ~owner:owner2 ~repo:repo2))
    true

(** Test cache effectiveness: demonstrates cache prevents duplicate work *)
let test_cache_effectiveness () =
  clear_all () ;
  let owner = "effectiveness-org" in
  let repo = "effectiveness-repo" in
  let config = create_test_config ~owner ~repo ~gitlab_domain:"gitlab.com" in
  
  (* Simulate first API call: cache miss, need to fetch *)
  check (option Repo_config.t) "first call: cache miss" (get_cached ~owner ~repo) None ;
  
  (* Simulate storing result after API call *)
  set_cached ~owner ~repo ~data:config ;
  
  (* Simulate second call for same repo: cache hit, no API call needed *)
  match get_cached ~owner ~repo with
  | Some cached ->
      (* Cache hit: we got the value without making another API call *)
      check string "second call: cache hit, same owner" cached.github_owner owner ;
      check (option string) "second call: cache hit, same gitlab_domain"
        cached.gitlab_domain (Some "gitlab.com")
  | None ->
      fail "Expected cache hit on second call (demonstrates cache prevents duplicate API calls)"

let () =
  run "Cache"
    [ ( "basic_operations"
      , [ test_case "basic get/set operations" `Quick test_cache_basic_operations ] )
    ; ( "isolation"
      , [ test_case "cache isolation between repos" `Quick test_cache_isolation ] )
    ; ( "expiration"
      , [ test_case "cache expiration logic" `Quick test_cache_expiration ] )
    ; ( "update"
      , [ test_case "cache update overwrites old value" `Quick test_cache_update ] )
    ; ( "cleanup"
      , [ test_case "cleanup_expired function" `Quick test_cache_cleanup ] )
    ; ( "clear_all"
      , [ test_case "clear_all removes all entries" `Quick test_cache_clear_all ] )
    ; ( "effectiveness"
      , [ test_case "cache prevents duplicate work" `Quick test_cache_effectiveness ] ) ]
```

**Update**: `tests/dune`

```lisp
(test
 (name cache_test)
 (libraries base bot-components config alcotest unix)
 (modules cache_test))
```

**Checklist**:
- [ ] Cache module compiles
- [ ] Tests pass
- [ ] Cache TTL works correctly
- [ ] Cleanup function works

---

### Phase 3: Create Auto-Detection Module

**Goal**: Implement API-based auto-detection with caching, error handling, and simplified scope.

**Important**: We focus on GitLab domain detection (most valuable) and installation ID caching. Complex label/job detection is optional and can be added later if needed.

#### Step 3.1: Create Auto-Detection Module

**File**: `src/config/auto_detection.ml` (NEW)

```ocaml
open Base
open Bot_components
open Utils
open Lwt.Infix

(** Logging helper *)
let log_info fmt = Printf.printf (fmt ^^ "\n%!")
let log_warn fmt = Printf.eprintf ("WARNING: " ^^ fmt ^^ "\n%!")
let log_error fmt = Printf.eprintf ("ERROR: " ^^ fmt ^^ "\n%!")

(** Auto-detect GitLab domain by searching all configured GitLab instances *)
let auto_detect_gitlab_info ~bot_info ~github_owner ~github_repo =
  let gitlab_instances = Bot_info.gitlab_instances_keys bot_info in
  let search_term = f "%s/%s" github_owner github_repo in
  
  log_info "Auto-detecting GitLab for %s/%s" github_owner github_repo ;
  
  Lwt_list.find_map_s
    (fun domain ->
      log_info "Searching GitLab instance: %s" domain ;
      GitLab_queries.search_projects ~bot_info ~gitlab_domain:domain ~search_term
      >>= function
      | Ok projects when not (List.is_empty projects) -> (
        (* Found matching project - use the first one *)
        match List.hd projects with
        | Some project ->
            log_info "Found GitLab project: %s/%s on %s" project.owner project.repo domain ;
            Lwt.return (Some (domain, project.owner, project.repo))
        | None ->
            Lwt.return None )
      | Ok _ ->
          log_info "No projects found on %s" domain ;
          Lwt.return None
      | Error err ->
          log_warn "Failed to search GitLab instance %s: %s" domain err ;
          Lwt.return None )
    gitlab_instances
  >>= function
  | Some (domain, owner, repo) ->
      Lwt.return (Some (domain, owner, repo))
  | None ->
      (* Not found - use default domain with same owner/repo *)
      log_info "No GitLab project found, using default domain" ;
      Lwt.return (Some (Defaults.gitlab_domain, github_owner, github_repo))

(** Auto-detect organization and team from GitHub API *)
let auto_detect_org_team ~bot_info ~owner ~repo =
  GitHub_queries.get_repository_info ~bot_info ~owner ~repo
  >>= function
  | Ok repo_info ->
      let org_name = Some repo_info.owner_login in
      (* Query teams in organization *)
      GitHub_queries.get_organization_teams ~bot_info ~org:repo_info.owner_login
      >>= (function
      | Ok teams when not (List.is_empty teams) ->
          (* Find common team names using exact match (more reliable) *)
          let preferred_team_names = ["contributors"; "maintainers"; "core"; "team"] in
          let team_name =
            List.find teams ~f:(fun team ->
                List.mem preferred_team_names
                  (String.lowercase team.slug)
                  ~equal:String.equal )
            |> Option.map ~f:(fun team -> team.slug)
            |> Option.value ~default:Defaults.team_name
          in
          log_info "Detected org: %s, team: %s" repo_info.owner_login team_name ;
          Lwt.return (Some (org_name, Some team_name))
      | Ok _ ->
          log_info "No teams found for org: %s" repo_info.owner_login ;
          Lwt.return (Some (org_name, Some Defaults.team_name))
      | Error err ->
          log_warn "Failed to get teams for org %s: %s" repo_info.owner_login err ;
          (* Fallback to generic default *)
          Lwt.return (Some (org_name, Some Defaults.team_name)) )
  | Error err ->
      log_warn "Failed to get repository info for %s/%s: %s" owner repo err ;
      Lwt.return None

(** Auto-detect labels from GitHub repository (optional - can be skipped if API fails) *)
let auto_detect_labels ~bot_info ~owner ~repo =
  GitHub_queries.get_all_labels ~bot_info ~owner ~repo
  >>= function
  | Ok label_list ->
      (* Match against common label patterns using exact or substring matching *)
      let find_label pattern =
        let normalized_pattern = String.lowercase pattern in
        List.find label_list ~f:(fun label ->
            let normalized = String.lowercase label.name in
            String.equal normalized normalized_pattern
            || String.is_substring normalized ~substring:normalized_pattern )
        |> Option.map ~f:(fun l -> l.name)
      in
      let labels =
        { Repo_config.needs_rebase= find_label "rebase"
        ; stale= find_label "stale"
        ; needs_full_ci= find_label "full"
        ; request_full_ci= find_label "request"
        ; needs_independent_fix= find_label "independent" }
      in
      log_info "Detected labels for %s/%s" owner repo ;
      Lwt.return (Some labels)
  | Error err ->
      log_warn "Failed to auto-detect labels for %s/%s: %s" owner repo err ;
      (* Return None - will use defaults *)
      Lwt.return None

(** Complete auto-detection from APIs with caching *)
let auto_detect_from_apis ~bot_info ~owner ~repo =
  (* Check cache first *)
  match Cache.get_cached ~owner ~repo with
  | Some cached ->
      log_info "Using cached auto-detection for %s/%s" owner repo ;
      Lwt.return cached
  | None ->
      log_info "Running auto-detection for %s/%s" owner repo ;
      let open Lwt.Syntax in
      (* Only detect GitLab domain and org/team - skip complex job/label detection for now *)
      let* gitlab_info = auto_detect_gitlab_info ~bot_info ~github_owner:owner ~github_repo:repo in
      let* org_team = auto_detect_org_team ~bot_info ~owner ~repo in
      let gitlab_domain, gitlab_owner, gitlab_repo =
        match gitlab_info with
        | Some (d, o, r) ->
            (Some d, Some o, Some r)
        | None ->
            (None, None, None)
      in
      let org_name, team_name =
        match org_team with
        | Some (o, t) ->
            (o, t)
        | None ->
            (None, None)
      in
      (* Optionally detect labels (non-blocking) *)
      let* labels = auto_detect_labels ~bot_info ~owner ~repo in
      
      let detected_config =
        { Repo_config.github_owner= owner
        ; github_repo= repo
        ; gitlab_domain
        ; gitlab_owner
        ; gitlab_repo
        ; github_installation_id= None (* Will be detected from webhooks *)
        ; github_project_number= None
        ; org_name
        ; team_name
        ; minimizer_url= Some Defaults.minimizer_url
        ; ci_config= Some Defaults.ci_config
        ; labels
        ; jobs= None (* Skip job detection - require explicit config *)
        ; documentation= None }
      in
      
      (* Cache the result *)
      Cache.set_cached ~owner ~repo ~data:detected_config ;
      
      Lwt.return detected_config
```

**File**: `src/config/auto_detection.mli` (NEW)

```ocaml
(** API-based auto-detection of repository configuration with caching *)

val auto_detect_from_apis :
     bot_info:Bot_components.Bot_info.t
  -> owner:string
  -> repo:string
  -> Repo_config.t Lwt.t
```

**Note**: We skip GitLab CI job detection for now because:
1. Requires proper YAML parsing (not regex)
2. Less critical than GitLab domain detection
3. Can be added later if needed
4. Users can provide explicit config for jobs

#### Step 3.2: Create Test Helpers

**File**: `tests/test_helpers.ml` (NEW)

```ocaml
open Base
open Bot_components
open Alcotest

(** Create a mock bot_info for testing *)
let create_mock_bot_info () =
  (* Adjust based on actual Bot_info.t structure *)
  Bot_info.create
    ~github_name:"test-bot"
    ~github_token:"test-token"
    ~github_webhook_secret:"test-secret"
    ~github_app_id:12345
    ~github_app_key:"test-key"
    ~gitlab_instances:[("gitlab.com", ("test-name", "test-token"))]
    ()

(** Mock GitHub API responses *)
module MockGitHub = struct
  let mock_repository_info ~owner ~repo =
    Ok
      { GitHub_queries.id= GitHub_ID.of_string "12345"
      ; owner_login= owner
      ; default_branch= "main" }

  let mock_organization_teams ~org =
    Ok
      [ {GitHub_queries.name= "Contributors"; slug= "contributors"}
      ; {GitHub_queries.name= "Maintainers"; slug= "maintainers"} ]

  let mock_all_labels ~owner ~repo =
    Ok
      [ {GitHub_queries.id= GitHub_ID.of_string "1"; name= "needs: rebase"}
      ; {GitHub_queries.id= GitHub_ID.of_string "2"; name= "stale"}
      ; {GitHub_queries.id= GitHub_ID.of_string "3"; name= "needs: full CI"} ]
end

(** Mock GitLab API responses *)
module MockGitLab = struct
  let mock_search_projects ~search_term =
    if String.is_substring search_term ~substring:"test-org/test-repo" then
      Ok
        [ { GitLab_queries.id= "123"
          ; full_path= "test-org/test-repo"
          ; owner= "test-org"
          ; repo= "test-repo" } ]
    else Ok []
end
```

#### Step 3.3: Test Auto-Detection Module

**File**: `tests/auto_detection_test.ml` (NEW)

```ocaml
open Base
open Repo_config
open Auto_detection
open Alcotest
open Lwt
open Test_helpers

let test_auto_detect_gitlab_info () =
  let bot_info = create_mock_bot_info () in
  let owner = "test-org" in
  let repo = "test-repo" in
  
  (* Mock GitLab search to return a project *)
  let result =
    Lwt_main.run
      (auto_detect_gitlab_info ~bot_info ~github_owner:owner ~github_repo:repo)
  in
  
  match result with
  | Some (domain, gl_owner, gl_repo) ->
      check string "gitlab_domain" domain "gitlab.com" ;
      check string "gitlab_owner" gl_owner owner ;
      check string "gitlab_repo" gl_repo repo
  | None ->
      fail "Expected to find GitLab project"

let test_auto_detect_org_team () =
  let bot_info = create_mock_bot_info () in
  let owner = "test-org" in
  let repo = "test-repo" in
  
  (* Mock GitHub API to return org and teams *)
  let result =
    Lwt_main.run (auto_detect_org_team ~bot_info ~owner ~repo)
  in
  
  match result with
  | Some (org_name, team_name) ->
      check (option string) "org_name" org_name (Some owner) ;
      check (option string) "team_name" team_name (Some "maintainers")
  | None ->
      fail "Expected to detect org and team"

let test_auto_detect_from_apis_with_cache () =
  let bot_info = create_mock_bot_info () in
  let owner = "test-org" in
  let repo = "test-repo" in
  
  (* Clear cache first *)
  Cache.clear_all () ;
  
  (* First call should run detection *)
  let result1 =
    Lwt_main.run (auto_detect_from_apis ~bot_info ~owner ~repo)
  in
  
  (* Second call should use cache *)
  let result2 =
    Lwt_main.run (auto_detect_from_apis ~bot_info ~owner ~repo)
  in
  
  (* Results should be identical *)
  check string "cached owner" result2.github_owner result1.github_owner ;
  check (option string) "cached gitlab_domain" result2.gitlab_domain
    result1.gitlab_domain

let () =
  run "Auto_detection"
    [ ( "api_detection"
      , [ test_case "detect gitlab info" `Quick test_auto_detect_gitlab_info
        ; test_case "detect org team" `Quick test_auto_detect_org_team
        ; test_case "caching works" `Quick test_auto_detect_from_apis_with_cache ] ) ]
```

**Update**: `tests/dune`

```lisp
(test
 (name auto_detection_test)
 (libraries base bot-components config alcotest lwt lwt.unix)
 (modules test_helpers auto_detection_test))
```

**Run Tests**:
```bash
dune exec tests/auto_detection_test.exe
```

**Checklist**:
- [ ] Auto-detection module compiles
- [ ] Tests pass
- [ ] Caching works
- [ ] Graceful handling of API failures
- [ ] Logging works correctly

---

### Phase 4: Create Config Resolver

**Goal**: Merge explicit config, auto-detected values, and defaults with correct priority.

#### Step 4.1: Create Config Resolver

**File**: `src/config/config_resolver.ml` (NEW)

```ocaml
open Base
open Utils

(** Merge two optional values with priority to the first *)
let merge_option opt1 opt2 =
  match opt1 with Some _ -> opt1 | None -> opt2

(** Merge nested config structures *)
let merge_ci_config opt1 opt2 =
  match (opt1, opt2) with
  | Some c1, Some c2 ->
      Some
        { Repo_config.full_ci_variable=
            merge_option c1.full_ci_variable c2.full_ci_variable
        ; skip_docker_variable=
            merge_option c1.skip_docker_variable c2.skip_docker_variable
        ; docker_path_pattern=
            merge_option c1.docker_path_pattern c2.docker_path_pattern }
  | Some c, None | None, Some c ->
      Some c
  | None, None ->
      None

let merge_label_config opt1 opt2 =
  match (opt1, opt2) with
  | Some l1, Some l2 ->
      Some
        { Repo_config.needs_rebase=
            merge_option l1.needs_rebase l2.needs_rebase
        ; stale= merge_option l1.stale l2.stale
        ; needs_full_ci= merge_option l1.needs_full_ci l2.needs_full_ci
        ; request_full_ci= merge_option l1.request_full_ci l2.request_full_ci
        ; needs_independent_fix=
            merge_option l1.needs_independent_fix l2.needs_independent_fix }
  | Some l, None | None, Some l ->
      Some l
  | None, None ->
      None

(** Merge two configurations with priority: Explicit > API > Defaults *)
let merge_configs explicit auto_detected defaults =
  { Repo_config.github_owner= explicit.github_owner
  ; github_repo= explicit.github_repo
  ; gitlab_domain=
      merge_option explicit.gitlab_domain
        (merge_option auto_detected.gitlab_domain defaults.gitlab_domain)
  ; gitlab_owner=
      merge_option explicit.gitlab_owner
        (merge_option auto_detected.gitlab_owner defaults.gitlab_owner)
  ; gitlab_repo=
      merge_option explicit.gitlab_repo
        (merge_option auto_detected.gitlab_repo defaults.gitlab_repo)
  ; github_installation_id=
      merge_option explicit.github_installation_id
        auto_detected.github_installation_id
  ; github_project_number=
      merge_option explicit.github_project_number
        auto_detected.github_project_number
  ; org_name=
      merge_option explicit.org_name
        (merge_option auto_detected.org_name defaults.org_name)
  ; team_name=
      merge_option explicit.team_name
        (merge_option auto_detected.team_name defaults.team_name)
  ; minimizer_url=
      merge_option explicit.minimizer_url
        (merge_option auto_detected.minimizer_url defaults.minimizer_url)
  ; ci_config=
      merge_ci_config explicit.ci_config
        (merge_option auto_detected.ci_config defaults.ci_config)
  ; labels=
      merge_label_config explicit.labels
        (merge_option auto_detected.labels defaults.labels)
  ; jobs=
      merge_option explicit.jobs
        (merge_option auto_detected.jobs defaults.jobs)
  ; documentation=
      merge_option explicit.documentation auto_detected.documentation }

(** Resolve final configuration with priority: Explicit > API > Defaults *)
(** Only runs auto-detection if explicit config is missing fields *)
let resolve_repo_config ~bot_info ~explicit_config =
  let open Lwt.Syntax in
  let owner = explicit_config.Repo_config.github_owner in
  let repo = explicit_config.github_repo in
  
  (* Step 1: Get defaults *)
  let defaults = Defaults.get_defaults ~owner ~repo in
  
  (* Step 2: Check if we need auto-detection (only if key fields are missing) *)
  let needs_auto_detection =
    Option.is_none explicit_config.gitlab_domain
    || Option.is_none explicit_config.org_name
  in
  
  let* auto_detected =
    if needs_auto_detection then (
      Printf.printf "Running auto-detection for %s/%s\n%!" owner repo ;
      Auto_detection.auto_detect_from_apis ~bot_info ~owner ~repo )
    else (
      Printf.printf "Skipping auto-detection for %s/%s (explicit config present)\n%!" owner repo ;
      Lwt.return
        { Repo_config.github_owner= owner
        ; github_repo= repo
        ; gitlab_domain= None
        ; gitlab_owner= None
        ; gitlab_repo= None
        ; github_installation_id= None
        ; github_project_number= None
        ; org_name= None
        ; team_name= None
        ; minimizer_url= None
        ; ci_config= None
        ; labels= None
        ; jobs= None
        ; documentation= None } )
  
  (* Step 3: Merge with priority: Explicit > API > Defaults *)
  let final_config = merge_configs explicit_config auto_detected defaults in
  
  Lwt.return final_config
```

**File**: `src/config/config_resolver.mli` (NEW)

```ocaml
(** Configuration resolver with priority: Explicit > API > Defaults *)

val resolve_repo_config :
     bot_info:Bot_components.Bot_info.t
  -> explicit_config:Repo_config.t
  -> Repo_config.t Lwt.t
```

#### Step 4.2: Test Config Resolver

**File**: `tests/config_resolver_test.ml` (NEW)

```ocaml
open Base
open Repo_config
open Config_resolver
open Defaults
open Alcotest
open Lwt
open Test_helpers

let test_merge_priority_explicit_overrides () =
  let bot_info = create_mock_bot_info () in
  let explicit_config =
    { github_owner= "explicit-org"
    ; github_repo= "explicit-repo"
    ; gitlab_domain= Some "gitlab.inria.fr"
    ; gitlab_owner= Some "coq"
    ; gitlab_repo= Some "coq"
    ; github_installation_id= Some 12345
    ; github_project_number= Some 11
    ; org_name= Some "explicit-org"
    ; team_name= Some "contributors"
    ; minimizer_url= Some "https://custom-minimizer.com"
    ; ci_config= None
    ; labels= None
    ; jobs= None
    ; documentation= None }
  in
  
  let result = Lwt_main.run (resolve_repo_config ~bot_info ~explicit_config) in
  
  (* Explicit config should take priority *)
  check string "explicit owner" result.github_owner "explicit-org" ;
  check (option string) "explicit gitlab_domain" result.gitlab_domain
    (Some "gitlab.inria.fr") ;
  check (option int) "explicit installation_id" result.github_installation_id
    (Some 12345) ;
  check (option string) "explicit org_name" result.org_name
    (Some "explicit-org") ;
  check (option string) "explicit team_name" result.team_name
    (Some "contributors")

let test_merge_priority_api_fills_gaps () =
  let bot_info = create_mock_bot_info () in
  let explicit_config =
    { github_owner= "test-org"
    ; github_repo= "test-repo"
    ; gitlab_domain= None
    ; gitlab_owner= None
    ; gitlab_repo= None
    ; github_installation_id= None
    ; github_project_number= None
    ; org_name= None
    ; team_name= None
    ; minimizer_url= None
    ; ci_config= None
    ; labels= None
    ; jobs= None
    ; documentation= None }
  in
  
  let result = Lwt_main.run (resolve_repo_config ~bot_info ~explicit_config) in
  
  (* API should fill in missing values *)
  check (option string) "api gitlab_domain" result.gitlab_domain
    (Some "gitlab.com") ;
  check (option string) "api org_name" result.org_name (Some "test-org") ;
  check (option string) "api team_name" result.team_name (Some "maintainers")

let test_merge_priority_defaults_fallback () =
  let bot_info = create_mock_bot_info () in
  let explicit_config =
    { github_owner= "unknown-org"
    ; github_repo= "unknown-repo"
    ; gitlab_domain= None
    ; gitlab_owner= None
    ; gitlab_repo= None
    ; github_installation_id= None
    ; github_project_number= None
    ; org_name= None
    ; team_name= None
    ; minimizer_url= None
    ; ci_config= None
    ; labels= None
    ; jobs= None
    ; documentation= None }
  in
  
  let result = Lwt_main.run (resolve_repo_config ~bot_info ~explicit_config) in
  
  (* Defaults should be used when API fails *)
  check (option string) "default gitlab_domain" result.gitlab_domain
    (Some "gitlab.com") ;
  check (option string) "default org_name" result.org_name
    (Some "unknown-org") ;
  check (option string) "default team_name" result.team_name
    (Some "maintainers") ;
  ( match result.ci_config with
  | Some ci ->
      check (option string) "default full_ci_variable" ci.full_ci_variable
        (Some "FULL_CI")
  | None ->
      fail "Expected CI config defaults" )

let () =
  run "Config_resolver"
    [ ( "merge_priority"
      , [ test_case "explicit overrides all" `Quick
            test_merge_priority_explicit_overrides
        ; test_case "API fills gaps" `Quick test_merge_priority_api_fills_gaps
        ; test_case "defaults fallback" `Quick
            test_merge_priority_defaults_fallback ] ) ]
```

**Update**: `tests/dune`

```lisp
(test
 (name config_resolver_test)
 (libraries base bot-components config alcotest lwt lwt.unix)
 (modules test_helpers config_resolver_test))
```

**Run Tests**:
```bash
dune exec tests/config_resolver_test.exe
```

**Checklist**:
- [ ] Config resolver compiles
- [ ] Tests pass
- [ ] Explicit config takes priority
- [ ] API fills gaps correctly
- [ ] Defaults used as fallback
- [ ] Auto-detection skipped when not needed

---

### Phase 5: Update Configuration Loading

**Goal**: Add installation ID caching from webhooks.

#### Step 5.1: Add Installation ID Cache

**File**: `src/config/repo_config.ml`

Add at the end:

```ocaml
(** Cache for installation IDs detected from webhooks *)
let installation_id_cache = Hashtbl.create (module String) (* "owner/repo" -> install_id *)

(** Update installation ID from webhook *)
let update_installation_id ~owner ~repo ~install_id repo_config_table =
  let key = f "%s/%s" owner repo in
  Hashtbl.set installation_id_cache ~key ~data:install_id ;
  (* Also update in repo config if exists *)
  match Hashtbl.find repo_config_table key with
  | Some config ->
      let updated_config =
        {config with github_installation_id= Some install_id}
      in
      Hashtbl.set repo_config_table ~key ~data:updated_config
  | None ->
      ()

(** Get installation ID (from cache or config) *)
let get_installation_id ~owner ~repo repo_config_table =
  let key = f "%s/%s" owner repo in
  match Hashtbl.find installation_id_cache key with
  | Some id ->
      Some id
  | None -> (
    match Hashtbl.find repo_config_table key with
    | Some config ->
        config.github_installation_id
    | None ->
        None )
```

**File**: `src/config/repo_config.mli`

Add:

```ocaml
val update_installation_id :
     owner:string
  -> repo:string
  -> install_id:int
  -> (string, t) Hashtbl.t
  -> unit

val get_installation_id :
     owner:string
  -> repo:string
  -> (string, t) Hashtbl.t
  -> int option
```

#### Step 5.2: Test Installation ID Caching

**File**: `tests/installation_id_test.ml` (NEW)

```ocaml
open Base
open Repo_config
open Alcotest

let test_installation_id_cache () =
  let table = create_repo_config_table (Utils.toml_of_string "") in
  let owner = "test-org" in
  let repo = "test-repo" in
  let install_id = 12345 in
  
  (* Initially no installation ID *)
  check (option int) "no install id initially"
    (get_installation_id ~owner ~repo table)
    None ;
  
  (* Update from webhook *)
  update_installation_id ~owner ~repo ~install_id table ;
  
  (* Should now have installation ID *)
  check (option int) "has install id after update"
    (get_installation_id ~owner ~repo table)
    (Some install_id) ;
  
  (* Should also update config if it exists *)
  let config_str =
    f {|
[repositories.test]
github = "%s/%s"
|} owner repo
  in
  let toml_data = Utils.toml_of_string config_str in
  let table2 = create_repo_config_table toml_data in
  update_installation_id ~owner ~repo ~install_id table2 ;
  
  ( match get_repo_config_opt ~owner ~repo table2 with
  | Some config ->
      check (option int) "config updated with install id"
        config.github_installation_id (Some install_id)
  | None ->
      fail "Expected config to exist" )

let test_installation_id_persistence () =
  let table = create_repo_config_table (Utils.toml_of_string "") in
  let owner = "test-org" in
  let repo = "test-repo" in
  
  (* Multiple updates should keep latest *)
  update_installation_id ~owner ~repo ~install_id:11111 table ;
  update_installation_id ~owner ~repo ~install_id:22222 table ;
  update_installation_id ~owner ~repo ~install_id:33333 table ;
  
  check (option int) "latest install id"
    (get_installation_id ~owner ~repo table)
    (Some 33333)

let () =
  run "Installation_id"
    [ ( "caching"
      , [ test_case "cache installation id" `Quick test_installation_id_cache
        ; test_case "persistence" `Quick test_installation_id_persistence ] ) ]
```

**Update**: `tests/dune`

```lisp
(test
 (name installation_id_test)
 (libraries base bot-components config alcotest)
 (modules installation_id_test))
```

**Run Tests**:
```bash
dune exec tests/installation_id_test.exe
```

**Checklist**:
- [ ] Installation ID cache compiles
- [ ] Tests pass
- [ ] Webhook events update cache
- [ ] Config table updated correctly

---

### Phase 6: Remove Hardcoded Checks

**Goal**: Replace all hardcoded repository checks with config-based logic.

#### Step 6.1: Update webhooks/github.ml

**File**: `src/webhooks/github.ml`

**Replace lines 289-326**:

```ocaml
  | Ok
      (Some install_id, PushEvent {owner; repo; base_ref; head_sha; commits_msg})
    -> (
      (* Update installation ID cache *)
      Repo_config.update_installation_id ~owner ~repo ~install_id
        repo_config_table ;
      
      (* Check if repo has config *)
      match get_repo_config_opt ~owner ~repo repo_config_table with
      | Some config when Option.is_some config.gitlab_domain ->
          (* Use config for GitHub-GitLab sync and backport *)
          let gitlab_domain, gl_owner, gl_repo =
            match
              (config.gitlab_domain, config.gitlab_owner, config.gitlab_repo)
            with
            | Some domain, Some gl_owner, Some gl_repo ->
                (domain, gl_owner, gl_repo)
            | _ ->
                (Defaults.gitlab_domain, owner, repo)
          in
          (fun () ->
            init_git_bare_repository ~bot_info
            >>= fun () ->
            let backport_action =
              if Option.is_some config.github_project_number then
                Bot_components.Github_installations
                .action_as_github_app_from_install_id ~bot_info ~key ~app_id
                  ~install_id (fun ~bot_info ->
                    Backport.push_action ~bot_info ~repo_config_table ~owner
                      ~repo ~base_ref ~commits_msg )
              else Lwt.return_unit
            in
            let mirror_action =
              Bot_components.Github_installations
              .action_as_github_app_from_install_id ~bot_info ~key ~app_id
                ~install_id
                (mirror_action ~gitlab_domain ~gh_owner:owner ~gh_repo:repo
                   ~gl_owner ~gl_repo ~base_ref ~head_sha () )
            in
            backport_action <&> mirror_action )
          |> Lwt.async ;
          Server.respond_string ~status:`OK
            ~body:(f "Processing push event for %s/%s." owner repo)
            ()
      | Some _ | None ->
          handle_push_event_for_repos ~bot_info ~key ~app_id ~install_id
            ~repo_config_table ~owner ~repo ~base_ref ~head_sha )
```

#### Step 6.2: Update actions/backport.ml

**File**: `src/actions/backport.ml`

**Replace function name and remove hardcoded checks**:

```ocaml
let push_action ~bot_info ~repo_config_table ~owner ~repo ~base_ref
    ~commits_msg =
  (* Get config to check if backport feature is enabled *)
  let config_opt = Repo_config.get_repo_config_opt ~owner ~repo repo_config_table in
  match config_opt with
  | Some config when Option.is_some config.github_project_number ->
      (* Feature enabled: has project number *)
      let project_number =
        Option.value_exn config.github_project_number
          ~message:"Project number should be present"
      in
      if
        String.is_substring base_ref ~substring:"refs/heads/master"
        || String.is_substring base_ref ~substring:"refs/heads/main"
      then (
        Stdio.printf "Push to main/master branch, analyzing merge commits.\n" ;
        Lwt_list.iter_s
          (fun commit_msg ->
            analyze_commit ~bot_info ~owner ~repo ~commit_msg ~project_number )
          commits_msg )
      else
        Lwt.return_unit
  | Some _ | None ->
      (* Feature not enabled or no config *)
      Lwt.return_unit
```

**Update**: `src/actions/backport.mli`

```ocaml
val push_action :
     bot_info:Bot_info.t
  -> repo_config_table:(string, Repo_config.t) Hashtbl.t
  -> owner:string
  -> repo:string
  -> base_ref:string
  -> commits_msg:string list
  -> unit Lwt.t
```

#### Step 6.3: Update actions/job.ml

**File**: `src/actions/job.ml`

**Replace lines 47-75**:

```ocaml
      (* Check if this is a bench job based on config *)
      let config_opt = Repo_config.get_repo_config_opt ~owner:gh_owner ~repo:gh_repo repo_config_table in
      let is_bench_job =
        match config_opt with
        | Some config -> (
          match config.jobs with
          | Some jobs -> (
            match jobs.bench with
            | Some bench_name ->
                String.equal job_info.build_name bench_name
            | None ->
                false )
          | None ->
              false )
        | None ->
            false
      in
      if is_bench_job then
        fetch_bench_artifacts ~bot_info ~github_repo_full_name ~pr_num
          ~head_commit ~build_id ~job_name ~job_url ~gitlab_repo_full_name ()
      else
        Lwt.return_unit
```

**Replace lines 69-75** (allow-failure handling):

```ocaml
              (* Check if custom job status handling is configured *)
              match config_opt with
              | Some config when Option.is_some config.jobs ->
                  (* Use config-based job status handling *)
                  ( (fun ~desc -> Lwt.return desc)
                  , fun ~bot_info:_ ~job_name:_ ~job_url:_ ~pr_num:_ ~head_commit:_
                        _gh_repo ~gitlab_repo_full_name:_ ->
                      Lwt.return_unit )
              | _ ->
                  ( (fun ~desc -> Lwt.return desc)
                  , fun ~bot_info:_ ~job_name:_ ~job_url:_ ~pr_num:_ ~head_commit:_
                        _gh_repo ~gitlab_repo_full_name:_ ->
                      Lwt.return_unit )
```

#### Step 6.4: Update actions/pr_sync.ml

**File**: `src/actions/pr_sync.ml`

**Replace lines 81-102**:

```ocaml
        (* Check if repo has config (feature enabled) *)
        has_repo_config ~owner ~repo repo_config_table
        &&
        let config = Repo_config.get_repo_config_opt ~owner ~repo repo_config_table in
        match config with
        | Some c -> (
          (* Check team membership to prevent CI file modification by untrusted contributors *)
          match (c.org_name, c.team_name) with
          | Some org, Some team ->
              let* is_member =
                GitHub_queries.get_team_membership ~bot_info ~org ~team
                  ~user:pr_author
              in
              ( match is_member with
              | Ok true ->
                  Lwt.return false (* Is member, allow CI changes *)
              | Ok false | Error _ ->
                  Lwt.return true (* Not member or error, prevent CI changes *) )
          | _ ->
              Lwt.return false )
        | None ->
            Lwt.return false
```

#### Step 6.5: Update ci/documentation.ml

**File**: `src/ci/documentation.ml`

**Replace lines 14-51** (remove fallback compatibility):

```ocaml
  (* Use repo_config - required, no fallback *)
  let repo_full_name, gitlab_url =
    match repo_config with
    | Some config ->
        let repo_name = f "%s/%s" config.github_owner config.github_repo in
        let url =
          match (config.gitlab_domain, config.gitlab_owner, config.gitlab_repo) with
          | Some domain, Some gl_owner, Some gl_repo ->
              f "https://%s/%s/%s/-/jobs/%d" domain gl_owner gl_repo job_id
          | _ ->
              (* Use defaults if not configured *)
              let domain = Option.value ~default:Defaults.gitlab_domain config.gitlab_domain in
              let gl_owner = Option.value ~default:config.github_owner config.gitlab_owner in
              let gl_repo = Option.value ~default:config.github_repo config.gitlab_repo in
              f "https://%s/%s/%s/-/jobs/%d" domain gl_owner gl_repo job_id
        in
        (repo_name, url)
    | None ->
        failwith "send_doc_url called without repo_config"
  in
```

**Remove fallback code** (lines 177-195):

```ocaml
  | _ ->
      (* No config provided - skip (config should always be provided) *)
      Lwt.return_unit
```

#### Step 6.6: Test No Hardcoded Patterns

**File**: `tests/no_hardcoded_patterns_test.ml` (NEW)

```ocaml
open Base
open Alcotest

(** Test that no hardcoded "rocq-prover" patterns exist in refactored code *)
let test_no_hardcoded_rocq_checks () =
  let test_repos =
    [ ("rocq-prover", "rocq")
    ; ("coq", "coq")
    ; ("math-comp", "math-comp")
    ; ("ocaml", "opam")
    ; ("test-org", "test-repo") ]
  in
  
  List.iter test_repos ~f:(fun (owner, repo) ->
      (* All repos should be treated the same way - no special cases *)
      let config_str = f {|
[repositories.test]
github = "%s/%s"
gitlab_domain = "gitlab.com"
|} owner repo
      in
      let toml_data = Utils.toml_of_string config_str in
      let table = Repo_config.create_repo_config_table toml_data in
      
      (* All repos should work with same generic logic *)
      Alcotest.check bool
        (f "repo %s/%s should have config" owner repo)
        (Repo_config.has_repo_config ~owner ~repo table)
        true )

let () =
  run "No_hardcoded_patterns"
    [ ( "regression"
      , [ test_case "no hardcoded rocq checks" `Quick
            test_no_hardcoded_rocq_checks ] ) ]
```

**Update**: `tests/dune`

```lisp
(test
 (name no_hardcoded_patterns_test)
 (libraries base bot-components config alcotest)
 (modules no_hardcoded_patterns_test))
```

**Run Tests**:
```bash
dune exec tests/no_hardcoded_patterns_test.exe
```

**Checklist**:
- [ ] All hardcoded checks removed
- [ ] Code compiles
- [ ] Tests pass
- [ ] No `String.equal owner "rocq-prover"` in codebase
- [ ] All functions use config table

---

### Phase 7: Rename Rocq-Specific Functions

**Goal**: Rename all `rocq_*` functions to generic names.

#### Step 7.1: Rename in backport.ml

**File**: `src/actions/backport.ml`

**Replace line 8**:
```ocaml
(* OLD *)
let rocq_push_action ~bot_info ~repo_config_table ~owner ~repo ~base_ref
    ~commits_msg =

(* NEW *)
let push_action ~bot_info ~repo_config_table ~owner ~repo ~base_ref
    ~commits_msg =
```

**Update all call sites** (in `webhooks/github.ml`):
```ocaml
(* OLD *)
Backport.rocq_push_action ~bot_info ~repo_config_table ~owner ~repo ...

(* NEW *)
Backport.push_action ~bot_info ~repo_config_table ~owner ~repo ...
```

**Update signature in `backport.mli`**:
```ocaml
(* OLD *)
val rocq_push_action : ...

(* NEW *)
val push_action : ...
```

#### Step 7.2: Rename in pr_sync.ml

**Find and replace**:
- `rocq_check_needs_rebase_pr` → `check_needs_rebase_pr`
- `rocq_check_stale_pr` → `check_stale_pr`

#### Step 7.3: Update job_status_rocq.ml (Future)

**Note**: Keep module name for backward compatibility, but rename internal functions:
- `extract_rocq_job_info` → `extract_job_info`
- `rocq_job_info` type → `job_info` type
- `rocq_summary_builder` → `custom_summary_builder`

#### Step 7.4: Test Function Names

**Verification**:
```bash
# Search for remaining rocq_ prefixes
grep -r "rocq_" src/

# Should only find:
# - job_status_rocq.ml (module name - OK)
# - Comments/documentation
```

**Checklist**:
- [ ] All `rocq_*` function names renamed
- [ ] All call sites updated
- [ ] Signatures updated in .mli files
- [ ] Code compiles
- [ ] No remaining `rocq_` function prefixes

---

### Phase 8: Update dune Files & Integration Testing

**Goal**: Update build files and run full integration tests.

#### Step 8.1: Update src/config/dune

**File**: `src/config/dune`

```lisp
(library
 (name config)
 (modules config repo_config defaults auto_detection config_resolver cache)
 (libraries base bot_components utils lwt lwt.unix))
```

#### Step 8.2: Update tests/dune

**File**: `tests/dune`

Add all new test entries:

```lisp
(test
 (name defaults_test)
 (libraries base bot-components config alcotest)
 (modules defaults_test))

(test
 (name cache_test)
 (libraries base bot-components config alcotest unix)
 (modules cache_test))

(test
 (name auto_detection_test)
 (libraries base bot-components config alcotest lwt lwt.unix)
 (modules test_helpers auto_detection_test))

(test
 (name config_resolver_test)
 (libraries base bot-components config alcotest lwt lwt.unix)
 (modules test_helpers config_resolver_test))

(test
 (name installation_id_test)
 (libraries base bot-components config alcotest)
 (modules installation_id_test))

(test
 (name no_hardcoded_patterns_test)
 (libraries base bot-components config alcotest)
 (modules no_hardcoded_patterns_test))

(test
 (name integration_test)
 (libraries base bot-components config alcotest lwt lwt.unix)
 (modules test_helpers integration_test))
```

#### Step 8.3: Integration Tests

**File**: `tests/integration_test.ml` (EXTEND)

```ocaml
open Base
open Bot_components
open Config
open Repo_config
open Alcotest
open Lwt
open Test_helpers

let test_minimal_config_with_auto_detection () =
  (* Test that a minimal config works with auto-detection *)
  let toml_str = {|
[repositories.simple_repo]
github = "simple-org/simple-repo"
|} in
  let toml_data = Utils.toml_of_string toml_str in
  let explicit_configs = parse_all_repo_configs toml_data in
  let explicit_config = List.hd_exn explicit_configs in
  
  let bot_info = create_mock_bot_info () in
  (* Clear cache for clean test *)
  Cache.clear_all () ;
  let final_config =
    Lwt_main.run (Config_resolver.resolve_repo_config ~bot_info ~explicit_config)
  in
  
  (* Should have auto-detected values *)
  check string "owner" final_config.github_owner "simple-org" ;
  check (option string) "auto-detected gitlab_domain" final_config.gitlab_domain
    (Some "gitlab.com") ;
  check (option string) "auto-detected org_name" final_config.org_name
    (Some "simple-org") ;
  check (option string) "auto-detected team_name" final_config.team_name
    (Some "maintainers")

let test_rocq_config_unchanged () =
  (* Test that existing rocq config still works *)
  let toml_str =
    {|
[repositories.rocq]
github = "rocq-prover/rocq"
github_installation_id = "1062161"
github_project_number = "11"
gitlab_domain = "gitlab.inria.fr"
gitlab_owner = "coq"
gitlab_repo = "coq"
org_name = "rocq-prover"
team_name = "contributors"
|} in
  let toml_data = Utils.toml_of_string toml_str in
  let configs = parse_all_repo_configs toml_data in
  let config = List.hd_exn configs in
  
  (* All explicit values should be preserved *)
  check string "rocq owner" config.github_owner "rocq-prover" ;
  check (option int) "rocq installation_id" config.github_installation_id
    (Some 1062161) ;
  check (option int) "rocq project_number" config.github_project_number
    (Some 11) ;
  check (option string) "rocq gitlab_domain" config.gitlab_domain
    (Some "gitlab.inria.fr") ;
  check (option string) "rocq org_name" config.org_name (Some "rocq-prover") ;
  check (option string) "rocq team_name" config.team_name
    (Some "contributors")

let test_webhook_updates_installation_id () =
  (* Test that webhook events update installation ID cache *)
  let table = create_repo_config_table (Utils.toml_of_string "") in
  let owner = "test-org" in
  let repo = "test-repo" in
  let install_id = 99999 in
  
  (* Simulate webhook event *)
  update_installation_id ~owner ~repo ~install_id table ;
  
  (* Verify installation ID is cached *)
  check (option int) "webhook install id cached"
    (get_installation_id ~owner ~repo table)
    (Some install_id)

let test_caching_prevents_duplicate_api_calls () =
  (* Test that cache prevents duplicate API calls *)
  let bot_info = create_mock_bot_info () in
  let owner = "test-org" in
  let repo = "test-repo" in
  let explicit_config =
    { github_owner= owner
    ; github_repo= repo
    ; gitlab_domain= None
    ; gitlab_owner= None
    ; gitlab_repo= None
    ; github_installation_id= None
    ; github_project_number= None
    ; org_name= None
    ; team_name= None
    ; minimizer_url= None
    ; ci_config= None
    ; labels= None
    ; jobs= None
    ; documentation= None }
  in
  
  (* Clear cache *)
  Cache.clear_all () ;
  
  (* First call should run detection *)
  let _result1 =
    Lwt_main.run (Config_resolver.resolve_repo_config ~bot_info ~explicit_config)
  in
  
  (* Second call should use cache (no API calls) *)
  let result2 =
    Lwt_main.run (Config_resolver.resolve_repo_config ~bot_info ~explicit_config)
  in
  
  (* Results should be identical *)
  check (option string) "cached gitlab_domain" result2.gitlab_domain
    (Some "gitlab.com")

let () =
  run "Integration"
    [ ( "end_to_end"
      , [ test_case "minimal config with auto-detection" `Quick
            test_minimal_config_with_auto_detection
        ; test_case "rocq config unchanged" `Quick test_rocq_config_unchanged
        ; test_case "webhook updates installation id" `Quick
            test_webhook_updates_installation_id
        ; test_case "caching prevents duplicate API calls" `Quick
            test_caching_prevents_duplicate_api_calls ] ) ]
```

**Update**: `tests/dune`

```lisp
(test
 (name integration_test)
 (libraries base bot-components config alcotest lwt lwt.unix)
 (modules test_helpers integration_test))
```

#### Step 8.4: Run All Tests

**Commands**:
```bash
# Run all tests
dune runtest

# Run specific test suites
dune exec tests/defaults_test.exe
dune exec tests/cache_test.exe
dune exec tests/auto_detection_test.exe
dune exec tests/config_resolver_test.exe
dune exec tests/installation_id_test.exe
dune exec tests/no_hardcoded_patterns_test.exe
dune exec tests/integration_test.exe

# Run with verbose output
dune runtest --verbose
```

**Checklist**:
- [ ] All dune files updated
- [ ] All tests compile
- [ ] All tests pass
- [ ] Integration tests pass
- [ ] Rocq config unchanged
- [ ] Minimal config works
- [ ] Caching works correctly

---

## Part 2: Performance & Error Handling

### Rate Limit Handling

**GitHub API**: 5,000 requests/hour
**GitLab API**: 2,000-10,000 requests/hour (varies by instance)

**Strategies**:
1. **Caching**: Cache auto-detection results for 1 hour (Phase 2.5)
2. **Lazy Loading**: Only auto-detect when config is missing
3. **Timeout**: 5-second timeout on all API calls
4. **Error Handling**: Return `None` on rate limit errors, use defaults

### Error Handling Best Practices

1. **Never crash on API failures**: Always return `None` or use defaults
2. **Log all failures**: Use `log_warn` or `log_error` for debugging
3. **Support partial detection**: Some fields can succeed while others fail
4. **Timeout all API calls**: Prevent hanging on slow/unresponsive APIs

### Performance Optimization

1. **Cache auto-detection results**: Avoid duplicate API calls
2. **Skip auto-detection when not needed**: If explicit config has all fields
3. **Cleanup expired cache entries**: Periodically remove old entries
4. **Async processing**: Don't block webhook processing

---

## Part 3: Configuration Examples

### Minimal Configuration (New Repo)

```toml
[repositories.my_simple_repo]
github = "my-org/my-repo"
# Everything else auto-detected via APIs or defaults!
```

**Auto-detected values:**
- GitLab domain: Searched via API or defaults to gitlab.com
- GitLab owner/repo: Same as GitHub or found via API
- Organization/team: Queried from GitHub API
- Installation ID: Detected from first webhook
- Labels: Queried from GitHub API (optional)
- Jobs: **Require explicit config** (skip auto-detection for now)

### Rocq Configuration (Complex - Needs Overrides)

```toml
[repositories.rocq]
github = "rocq-prover/rocq"
github_project_number = "11"  # Enables backport feature
gitlab_domain = "gitlab.inria.fr"  # Override default
gitlab_owner = "coq"  # Different from GitHub
gitlab_repo = "coq"   # Different from GitHub
org_name = "rocq-prover"
team_name = "contributors"
minimizer_url = "https://github.com/rocq-community/run-coq-bug-minimizer/actions"

[repositories.rocq.ci]
full_ci_variable = "FULL_CI"
skip_docker_variable = "SKIP_DOCKER"
docker_path_pattern = "dev/ci/docker/.*Dockerfile.*"

[repositories.rocq.labels]
needs_rebase = "needs: rebase"
stale = "stale"
needs_full_ci = "needs: full CI"
request_full_ci = "request: full CI"
needs_independent_fix = "needs: independent fix"

[repositories.rocq.jobs]
bench = "bench"
doc_refman = "doc:refman|doc:refman-pdf"
doc_init = "doc:stdlib:dune:init"
doc_stdlib = "doc:stdlib|doc:stdlib:dune"
doc_ml_api = "doc:ml-api:odoc"

[repositories.rocq.documentation]
refman_path = "_build/default/doc/refman-html/index.html"
corelib_path = "_build/default/doc/corelib/html/index.html"
stdlib_path = "_build/default/doc/stdlib/html/index.html"
ml_api_path = "_build/default/_doc/_html/index.html"
```

---

## Part 4: Verification Checklist

### Code Quality Checks
- [ ] No `String.equal owner "rocq-prover"` in codebase
- [ ] No `String.equal repo "rocq"` in codebase
- [ ] No hardcoded `"gitlab.inria.fr"` patterns
- [ ] All detection via APIs or generic defaults
- [ ] Functions renamed from `rocq_*` to generic names
- [ ] All API calls have timeouts
- [ ] Error handling implemented throughout

### Functionality Checks
- [ ] Rocq behavior unchanged with explicit config
- [ ] New repos work with minimal config (1-2 lines)
- [ ] Installation IDs cached from webhooks
- [ ] API detection works for common repos
- [ ] Defaults applied when APIs unavailable
- [ ] Caching prevents duplicate API calls

### Performance Checks
- [ ] API calls are asynchronous
- [ ] Config resolution cached per repo (1 hour TTL)
- [ ] No duplicate API calls (cache working)
- [ ] Timeouts prevent hanging
- [ ] Rate limit errors handled gracefully

### Test Coverage
- [ ] All phases have tests
- [ ] All tests pass
- [ ] Integration tests pass
- [ ] Regression tests pass
- [ ] Cache tests pass
- [ ] Error handling tests pass

---

## Part 5: Migration Steps

### For Existing Rocq Configuration

1. **No changes needed** - existing config continues to work
2. Test that behavior is unchanged
3. Optional: Remove redundant fields that match defaults

### For Adding New Repositories

1. Add minimal config:
   ```toml
   [repositories.new_repo]
   github = "owner/repo"
   ```

2. Start webhook to trigger installation ID detection

3. Monitor logs for auto-detected values

4. Add explicit overrides only if needed:
   - GitLab domain/owner/repo (if different from GitHub)
   - Labels (if different from defaults)
   - Jobs (required - no auto-detection)
   - CI config (if different from defaults)

---

## Summary

This implementation:
1. ✅ **Reuses existing code** - Leverages bot-components APIs
2. ✅ **No duplication** - Uses existing GitHub/GitLab query functions
3. ✅ **Generic** - No hardcoded repo-specific patterns
4. ✅ **API-based** - Detection via GitHub/GitLab APIs with caching
5. ✅ **Optimized** - Minimal config for simple repos, caching prevents rate limits
6. ✅ **Backward compatible** - Rocq config unchanged
7. ✅ **Robust** - Error handling, timeouts, graceful degradation
8. ✅ **Thoroughly tested** - Comprehensive test suite with unit, integration, and regression tests

**Rocq Status**: Just a configured instance with specific values - no special code!

**Implementation Order**: Follow phases 1-8 sequentially. Each phase includes implementation steps and corresponding tests. Complete one phase before moving to the next.

**Key Improvements**:
- Caching layer prevents rate limit issues
- Timeouts prevent hanging on slow APIs
- Error handling ensures graceful degradation
- Simplified auto-detection scope (focus on GitLab domain)
- Skip complex job detection (require explicit config)
