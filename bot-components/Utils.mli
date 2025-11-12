val f : ('a, unit, string) format -> 'a

val toml_of_string : string -> Toml.Types.table

val toml_of_file : string -> Toml.Types.table

val subkey_value : Toml.Types.table -> string -> string -> string option

val find : string -> Toml.Types.table -> Toml.Types.value

val list_table_keys : Toml.Types.table -> string list

val days_elapsed : float -> int

val apply_throttle : int -> ('a -> bool Lwt.t) -> 'a list -> unit Lwt.t

val report_on_posting_comment : (string, string) result -> unit Lwt.t

val extract_backport_info :
  bot_info:Bot_info.t -> description:string -> GitHub_types.backport_info list

val with_timeout : timeout:float -> 'a Lwt.t -> 'a Lwt.t
