(** Caching layer for auto-detection results *)

val get_cached : owner:string -> repo:string -> Repo_config.t option

val set_cached : owner:string -> repo:string -> data:Repo_config.t -> unit

val cleanup_expired : unit -> unit

val clear_all : unit -> unit

val set_cached_with_timestamp :
  owner:string -> repo:string -> data:Repo_config.t -> timestamp:float -> unit
(** [FOR TESTING ONLY] Set cache entry with custom timestamp.
    Allows testing expiration without waiting real time. *)
