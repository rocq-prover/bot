val f : ('a, unit, string) format -> 'a

val toml_of_string : string -> Toml.Types.table

val toml_of_file : string -> Toml.Types.table

val subkey_value : Toml.Types.table -> string -> string -> string option

val subkey_table :
  Toml.Types.table -> string -> string -> Toml.Types.table option

val subkey_int : Toml.Types.table -> string -> string -> int option

val key_value : Toml.Types.table -> string -> string option

val key_array : Toml.Types.table -> string -> string list option

val key_bool : Toml.Types.table -> string -> bool option

val key_int : Toml.Types.table -> string -> int option

val find : string -> Toml.Types.table -> Toml.Types.value

val list_table_keys : Toml.Types.table -> string list

val days_elapsed : float -> int

val apply_throttle : int -> ('a -> bool Lwt.t) -> 'a list -> unit Lwt.t

val report_on_posting_comment : (string, string) result -> unit Lwt.t

val extract_backport_info :
  bot_info:Bot_info.t -> description:string -> GitHub_types.backport_info list
