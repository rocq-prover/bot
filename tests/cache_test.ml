open Alcotest
open Cache
open Test_helpers

(* Test basic cache get/set operations *)
let test_cache_basic_operations () =
  clear_all () ;
  let owner = "test-org" in
  let repo = "test-repo" in
  let config = create_test_config ~owner ~repo ~gitlab_domain:"gitlab.com" in
  (* Cache miss: no entry initially *)
  check
    (option repo_config_testable)
    "cache miss initially" (get_cached ~owner ~repo) None ;
  (* Set cache *)
  set_cached ~owner ~repo ~data:config ;
  (* Cache hit: should retrieve cached value *)
  match get_cached ~owner ~repo with
  | Some cached ->
      check string "cached owner matches" cached.github_owner owner ;
      check string "cached repo matches" cached.github_repo repo ;
      check (option string) "cached gitlab_domain matches" cached.gitlab_domain
        (Some "gitlab.com") ;
      check (option string) "cached org_name matches" cached.org_name
        (Some owner)
  | None ->
      fail "Expected cache hit but got cache miss"

(* Test cache isolation: different repos don't interfere*)
let test_cache_isolation () =
  clear_all () ;
  let config1 =
    create_test_config ~owner:"org1" ~repo:"repo1" ~gitlab_domain:"gitlab.com"
  in
  let config2 =
    create_test_config ~owner:"org2" ~repo:"repo2"
      ~gitlab_domain:"gitlab.inria.fr"
  in
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
  check
    (option repo_config_testable)
    "cache miss for non-existent repo"
    (get_cached ~owner:"org3" ~repo:"repo3")
    None

(* Test cache expiration: entries expire after TTL *)
let test_cache_expiration () =
  clear_all () ;
  let owner = "expire-test-org" in
  let repo = "expire-test-repo" in
  let config = create_test_config ~owner ~repo ~gitlab_domain:"gitlab.com" in
  let now = Unix.time () in
  (* Test 1: Set cache with expired timestamp (older than TTL) *)
  let expired_timestamp = now -. 3700.0 in
  (* 3700 seconds = more than 1 hour *)
  set_cached_with_timestamp ~owner ~repo ~data:config
    ~timestamp:expired_timestamp ;
  (* Expired entry should not be returned (cache miss) *)
  check
    (option repo_config_testable)
    "expired entry returns None" (get_cached ~owner ~repo) None ;
  (* Test 2: Set cache with recent timestamp (within TTL) *)
  let recent_timestamp = now -. 1800.0 in
  (* 1800 seconds = 30 minutes, less than 1 hour *)
  set_cached_with_timestamp ~owner ~repo ~data:config
    ~timestamp:recent_timestamp ;
  (* Recent entry should be returned (cache hit) *)
  check bool "recent entry is valid (cache hit)"
    (Option.is_some (get_cached ~owner ~repo))
    true ;
  (* Test 3: Set cache with timestamp exactly at TTL boundary *)
  let boundary_timestamp = now -. 3600.0 in
  (* Exactly 1 hour ago *)
  set_cached_with_timestamp ~owner ~repo ~data:config
    ~timestamp:boundary_timestamp ;
  (* Entry at boundary should be expired (age >= TTL, so not valid) *)
  check
    (option repo_config_testable)
    "entry at TTL boundary is expired" (get_cached ~owner ~repo) None ;
  (* Test 4: Set cache with timestamp just before TTL *)
  let just_valid_timestamp = now -. 3599.0 in
  (* 1 second before TTL *)
  set_cached_with_timestamp ~owner ~repo ~data:config
    ~timestamp:just_valid_timestamp ;
  (* Entry just before boundary should be valid *)
  check bool "entry just before TTL boundary is valid"
    (Option.is_some (get_cached ~owner ~repo))
    true

(* Test cache update: setting new value overwrites old *)
let test_cache_update () =
  clear_all () ;
  let owner = "update-test-org" in
  let repo = "update-test-repo" in
  let config1 = create_test_config ~owner ~repo ~gitlab_domain:"gitlab.com" in
  let config2 =
    create_test_config ~owner ~repo ~gitlab_domain:"gitlab.inria.fr"
  in
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
  match get_cached ~owner ~repo with
  | Some cached ->
      check (option string) "updated gitlab_domain" cached.gitlab_domain
        (Some "gitlab.inria.fr")
  | None ->
      fail "Expected updated cached value"

(* Test cleanup_expired: removes expired entries *)
let test_cleanup_expired () =
  clear_all () ;
  let owner1 = "cleanup-org1" in
  let repo1 = "cleanup-repo1" in
  let owner2 = "cleanup-org2" in
  let repo2 = "cleanup-repo2" in
  let config1 =
    create_test_config ~owner:owner1 ~repo:repo1 ~gitlab_domain:"gitlab.com"
  in
  let config2 =
    create_test_config ~owner:owner2 ~repo:repo2 ~gitlab_domain:"gitlab.com"
  in
  (* Cache both repos *)
  set_cached ~owner:owner1 ~repo:repo1 ~data:config1 ;
  set_cached ~owner:owner2 ~repo:repo2 ~data:config2 ;
  (* Verify both are cached *)
  check bool "both repos cached before cleanup"
    ( Option.is_some (get_cached ~owner:owner1 ~repo:repo1)
    && Option.is_some (get_cached ~owner:owner2 ~repo:repo2) )
    true ;
  (* Run cleanup (should keep valid entries, remove expired ones) *)
  cleanup_expired () ;
  (* Verify both are still cached *)
  check bool "both repos still cached after cleanup (recent entries)"
    ( Option.is_some (get_cached ~owner:owner1 ~repo:repo1)
    && Option.is_some (get_cached ~owner:owner2 ~repo:repo2) )
    true

(* Test clear_all: removes all caches entries *)
let test_cache_clear_all () =
  clear_all () ;
  let owner1 = "clear-org1" in
  let repo1 = "clear-repo1" in
  let owner2 = "clear-org2" in
  let repo2 = "clear-repo2" in
  let config1 =
    create_test_config ~owner:owner1 ~repo:repo1 ~gitlab_domain:"gitlab.com"
  in
  let config2 =
    create_test_config ~owner:owner2 ~repo:repo2 ~gitlab_domain:"gitlab.com"
  in
  (* Cache both repos *)
  set_cached ~owner:owner1 ~repo:repo1 ~data:config1 ;
  set_cached ~owner:owner2 ~repo:repo2 ~data:config2 ;
  (* Verify both are cached *)
  check bool "both repos cached before clear"
    ( Option.is_some (get_cached ~owner:owner1 ~repo:repo1)
    && Option.is_some (get_cached ~owner:owner2 ~repo:repo2) )
    true ;
  (* Clear all cache *)
  clear_all () ;
  (* Verify both are now cache misses *)
  check bool "both repos cleared after clear_all"
    ( Option.is_none (get_cached ~owner:owner1 ~repo:repo1)
    && Option.is_none (get_cached ~owner:owner2 ~repo:repo2) )
    true

(* Test cache effectiveness: demonstrates cache prevents duplicate work *)
let test_cache_effectiveness () =
  clear_all () ;
  let owner = "effectiveness-org" in
  let repo = "effectiveness-repo" in
  let config = create_test_config ~owner ~repo ~gitlab_domain:"gitlab.com" in
  (* Simulate first API call: cache miss, need to fetch *)
  check
    (option repo_config_testable)
    "first call: cache miss" (get_cached ~owner ~repo) None ;
  (* Simulate storing result after API call *)
  set_cached ~owner ~repo ~data:config ;
  (* Simulate second call for same repo: cache hit, no API call needed *)
  match get_cached ~owner ~repo with
  | Some cached ->
      (* Cache hit: we got the value without making another API call *)
      check string "second call: cache hit, same owner" cached.github_owner
        owner ;
      check (option string) "second call: cache hit, same gitlab_domain"
        cached.gitlab_domain (Some "gitlab.com")
  | None ->
      fail
        "Expected cached value on second call (demonstrates cache prevents \
         duplicate API calls)"

let () =
  run "Cache"
    [ ( "basic_operations"
      , [test_case "basic get/set operations" `Quick test_cache_basic_operations]
      )
    ; ( "isolation"
      , [test_case "cache isolation between repos" `Quick test_cache_isolation]
      )
    ; ( "expiration"
      , [test_case "cache expiration after TTL" `Quick test_cache_expiration] )
    ; ( "update"
      , [test_case "cache update overwrites old value" `Quick test_cache_update]
      )
    ; ( "cleanup"
      , [test_case "cleanup_expired function" `Quick test_cleanup_expired] )
    ; ( "clear_all"
      , [test_case "clear_all removes all entries" `Quick test_cache_clear_all]
      )
    ; ( "effectiveness"
      , [ test_case "cache prevents duplicate work" `Quick
            test_cache_effectiveness ] ) ]
