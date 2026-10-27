open Base

(******************************************************************************)
(* Regex/Pattern Matching Functions                                           *)
(******************************************************************************)

let string_match ~regexp ?(pos = 0) string =
  try
    let (_ : int) = Str.search_forward (Str.regexp regexp) string pos in
    true
  with Stdlib.Not_found -> false

let rec fold_string_matches ~regexp ~f ~init ?(pos = 0) string =
  if string_match ~regexp ~pos string then
    let pos = Str.match_end () in
    f (fun () -> fold_string_matches ~regexp ~f ~init ~pos string)
  else init

let map_string_matches ~regexp ~f string =
  fold_string_matches ~regexp
    ~f:(fun rest ->
      let v = f () in
      v :: rest () )
    ~init:[] string

let iter_string_matches ~regexp ~f string =
  fold_string_matches ~regexp ~f:(fun rest -> f () ; rest ()) ~init:() string

let find_regex_in_lines ~regexps lines =
  List.find_map lines ~f:(fun line ->
      List.find_map regexps ~f:(fun regexp ->
          if string_match ~regexp line then Some (Str.matched_group 1 line)
          else None ) )

let find_all_regex_in_lines ~regexps lines =
  List.filter_map lines ~f:(fun line ->
      List.find_map regexps ~f:(fun regexp ->
          if string_match ~regexp line then Some (Str.matched_group 1 line)
          else None ) )

(******************************************************************************)
(* String Extraction and Manipulation                                         *)
(******************************************************************************)

let first_line_of_string s =
  if string_match ~regexp:"\\(.*\\)\n" s then Str.matched_group 1 s else s

let remove_between s i j =
  String.sub ~pos:0 ~len:i s ^ String.sub s ~pos:j ~len:(String.length s - j)

type quote = Single | Double

let split_shell_words ~preserve_syntax input =
  let is_whitespace = function
    | ' ' | '\t' | '\n' | '\r' | '\011' | '\012' ->
        true
    | _ ->
        false
  in
  let buffer = Buffer.create (String.length input) in
  let add_syntax char = if preserve_syntax then Buffer.add_char buffer char in
  let finish_token token_started tokens =
    if token_started then Buffer.contents buffer :: tokens else tokens
  in
  let length = String.length input in
  let rec split index quote token_started tokens =
    if index = length then
      match quote with
      | Some delimiter ->
          Error
            (Printf.sprintf "unterminated %c quote"
               (match delimiter with Single -> '\'' | Double -> '"') )
      | None ->
          Ok (List.rev (finish_token token_started tokens))
    else
      let char = input.[index] in
      match quote with
      | None when is_whitespace char ->
          let tokens = finish_token token_started tokens in
          Buffer.clear buffer ;
          split (index + 1) None false tokens
      | None when Char.equal char '\\' ->
          if index + 1 = length then Error "trailing escape character"
          else
            let escaped = input.[index + 1] in
            if Char.equal escaped '\n' then
              split (index + 2) None token_started tokens
            else (
              add_syntax char ;
              Buffer.add_char buffer escaped ;
              split (index + 2) None true tokens )
      | None when Char.equal char '\'' ->
          add_syntax char ;
          split (index + 1) (Some Single) true tokens
      | None when Char.equal char '"' ->
          add_syntax char ;
          split (index + 1) (Some Double) true tokens
      | None ->
          Buffer.add_char buffer char ;
          split (index + 1) None true tokens
      | Some Single when Char.equal char '\'' ->
          add_syntax char ;
          split (index + 1) None true tokens
      | Some Single ->
          Buffer.add_char buffer char ;
          split (index + 1) quote true tokens
      | Some Double when Char.equal char '"' ->
          add_syntax char ;
          split (index + 1) None true tokens
      | Some Double when Char.equal char '\\' ->
          if index + 1 = length then Error "unterminated \" quote"
          else
            let escaped = input.[index + 1] in
            if Char.equal escaped '\n' then split (index + 2) quote true tokens
            else if List.mem ['"'; '\\'; '$'; '`'] escaped ~equal:Char.equal
            then (
              add_syntax char ;
              Buffer.add_char buffer escaped ;
              split (index + 2) quote true tokens )
            else (
              Buffer.add_char buffer char ;
              split (index + 1) quote true tokens )
      | Some Double ->
          Buffer.add_char buffer char ;
          split (index + 1) quote true tokens
  in
  split 0 None false []

let split_on_unquoted_whitespace input =
  split_shell_words ~preserve_syntax:true input

let parse_key_value_arguments input =
  match split_shell_words ~preserve_syntax:false input with
  | Error _ as error ->
      error
  | Ok arguments ->
      let rec parse parsed = function
        | [] ->
            Ok (List.rev parsed)
        | argument :: arguments -> (
          match Stdlib.String.index_opt argument '=' with
          | None when String.is_empty argument ->
              Error (Printf.sprintf "argument %S has an empty key" argument)
          | None ->
              parse ((argument, None) :: parsed) arguments
          | Some 0 ->
              Error (Printf.sprintf "argument %S has an empty key" argument)
          | Some separator ->
              let key = String.sub argument ~pos:0 ~len:separator in
              let value =
                String.sub argument ~pos:(separator + 1)
                  ~len:(String.length argument - separator - 1)
              in
              parse ((key, Some value) :: parsed) arguments )
      in
      parse [] arguments

(******************************************************************************)
(* Formatting Functions                                                       *)
(******************************************************************************)

let code_wrap str = Printf.sprintf "```\n%s\n```" str

let markdown_details summary text =
  Printf.sprintf "<details>\n<summary>%s</summary>\n\n%s\n\n</details>\n"
    summary text

let markdown_link text url = Printf.sprintf "[%s](%s)" text url

(******************************************************************************)
(* HTML/Comment Processing                                                    *)
(******************************************************************************)

let trim_comments comment =
  let rec aux comment begin_ in_comment =
    if not in_comment then
      try
        let begin_ = Str.search_forward (Str.regexp "<!--") comment 0 in
        aux comment begin_ true
      with Stdlib.Not_found -> comment
    else
      try
        let end_ = Str.search_forward (Str.regexp "-->") comment begin_ in
        aux (remove_between comment begin_ (end_ + 3)) 0 false
      with Stdlib.Not_found -> comment
  in
  aux comment 0 false

(******************************************************************************)
(* Bot-specific String Processing                                             *)
(******************************************************************************)

let strip_quoted_bot_name ~github_bot_name body =
  (* If someone says "`@coqbot minimize foo`", (with backticks), we
     don't want to treat that as them tagging coqbot, so we adjust
     the tagging to "@`coqbot minimize foo`" so that the matching
     below doesn't pick up the name *)
  Str.global_replace
    (Str.regexp
       (Printf.sprintf "\\(`\\|<code>\\)@%s:? " (Str.quote github_bot_name)) )
    (Printf.sprintf "@\\1%s " (Str.quote github_bot_name))
    body

let clean_gitlab_trace trace =
  trace
  |> Str.global_replace (Str.regexp "\027\\[[0-9;]*m") ""
  |> Str.global_replace (Str.regexp "\027\\[0K") ""
  |> Str.global_replace (Str.regexp "section_start:[0-9]*:[a-z_]*\r") ""
  |> Str.global_replace (Str.regexp "section_end:[0-9]*:[a-z_]*\r") ""
  |> String.split_lines

let shorten_ci_check_name target =
  target
  |> Str.global_replace (Str.regexp "GitLab CI job") ""
  |> Str.global_replace (Str.regexp "(pull request)") ""
  |> Str.global_replace (Str.regexp "(branch)") ""
  |> Stdlib.String.trim

(******************************************************************************)
(* Hashtable Formatting                                                       *)
(******************************************************************************)

let string_of_mapping mapping =
  Hashtbl.fold ~init:""
    ~f:(fun ~key ~data acc -> acc ^ Printf.sprintf "(%s, %s)\n" key data)
    mapping
