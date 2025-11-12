open Base
open Bot_components.Utils

(** Cache entry with timestamp for TTL *)
type 'a cache_entry = {data: 'a; timestamp: float}

(** Cache TTL: 1 hour (3600 seconds) *)
let cache_ttl = 3600.0

(** In-memory cache: "owner/repo" -> (detected_config, timestamp) *)
let auto_detection_cache : (string, Repo_config.t cache_entry) Hashtbl.t =
  Hashtbl.create (module String)

(** Check if cache entry is still valid *)
let is_valid entry =
  let age = Unix.time () -. entry.timestamp in
  Float.(age < cache_ttl)

(** Get cached auto-detection result *)
let get_cached ~owner ~repo =
  let key = f "%s/%s" owner repo in
  match Hashtbl.find auto_detection_cache key with
  | Some entry when is_valid entry ->
      Some entry.data
  | Some _ | None ->
      None

(**Store auto-detection result in cache*)
let set_cached ~owner ~repo ~data =
  let key = f "%s/%s" owner repo in
  let entry = {data; timestamp= Unix.time ()} in
  Hashtbl.set auto_detection_cache ~key ~data:entry

(** Clear expired entries from cache *)
let cleanup_expired () =
  let now = Unix.time () in
  Hashtbl.filter_inplace auto_detection_cache ~f:(fun entry ->
      Float.(now -. entry.timestamp < cache_ttl) )

(** Clear all cache entries *)
let clear_all () = Hashtbl.clear auto_detection_cache

(** [FOR TESTING ONLY] Set cache entry with custom timestamp.
    This allows testing expiration without waiting real time. *)
let set_cached_with_timestamp ~owner ~repo ~data ~timestamp =
  let key = f "%s/%s" owner repo in
  let entry = {data; timestamp} in
  Hashtbl.set auto_detection_cache ~key ~data:entry
