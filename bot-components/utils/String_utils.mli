(* ========================================================================== *)
(* Regex/Pattern Matching Functions *)
(* ========================================================================== *)

val string_match : regexp:string -> ?pos:int -> string -> bool

val find_regex_in_lines : regexps:string list -> string list -> string option

val find_all_regex_in_lines : regexps:string list -> string list -> string list

val fold_string_matches :
  regexp:string -> f:((unit -> 'a) -> 'a) -> init:'a -> ?pos:int -> string -> 'a

val map_string_matches : regexp:string -> f:(unit -> 'a) -> string -> 'a list

val iter_string_matches : regexp:string -> f:(unit -> unit) -> string -> unit

(* ========================================================================== *)
(* String Extraction and Manipulation *)
(* ========================================================================== *)

val first_line_of_string : string -> string

val remove_between : string -> int -> int -> string

val split_on_unquoted_whitespace : string -> (string list, string) Result.t
(** [split_on_unquoted_whitespace input] splits [input] at ASCII whitespace
    outside single or double quotes. Shell quote and escape syntax is recognized
    and preserved in the returned tokens.

    Returns an error for an unterminated quote or a trailing backslash. *)

val parse_key_value_arguments :
  string -> ((string * string option) list, string) Result.t
(** [parse_key_value_arguments input] parses shell-style [key=value] words.
    Quote and escape syntax is consumed. A missing equal sign produces a [None]
    value; an equal sign produces [Some value], including [Some ""] for an
    explicitly empty value. Values may contain additional equal signs.

    Returns an error if quoting is malformed or an argument has an empty key. *)

(* ========================================================================== *)
(* Formatting Functions *)
(* ========================================================================== *)

val code_wrap : string -> string

(* ========================================================================== *)
(* HTML/Comment Processing *)
(* ========================================================================== *)

val markdown_details : string -> string -> string

val markdown_link : string -> string -> string

val trim_comments : string -> string

(* ========================================================================== *)
(* Bot-specific String Processing *)
(* ========================================================================== *)

val strip_quoted_bot_name : github_bot_name:string -> string -> string

val clean_gitlab_trace : string -> string list

val shorten_ci_check_name : string -> string

val string_of_mapping : (string, string) Base.Hashtbl.t -> string
