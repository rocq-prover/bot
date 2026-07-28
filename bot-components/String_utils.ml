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

let%expect_test "strip_quoted_bot_name" =
  Stdio.printf "%s\n"
    (strip_quoted_bot_name ~github_bot_name:"coqbot"
       {|>this didn't produce a pipeline for some reason\r\n\r\nI think that this is normal. @herbelin was maybe expecting that adding the `request: full CI` label would trigger a new run immediately, but the semantics is that this label will produce such a full CI run at the next update (next push) of this PR. Cf. the [documentation](https://github.com/coq/coq/blob/master/CONTRIBUTING.md#understanding-automatic-feedback):\r\n\r\n>you can request a full run of the CI by putting the `request: full CI` label before pushing to your PR branch, or by commenting `@coqbot: run full CI` after having pushed. |} ) ;
  [%expect
    {| >this didn't produce a pipeline for some reason\r\n\r\nI think that this is normal. @herbelin was maybe expecting that adding the `request: full CI` label would trigger a new run immediately, but the semantics is that this label will produce such a full CI run at the next update (next push) of this PR. Cf. the [documentation](https://github.com/coq/coq/blob/master/CONTRIBUTING.md#understanding-automatic-feedback):\r\n\r\n>you can request a full run of the CI by putting the `request: full CI` label before pushing to your PR branch, or by commenting @`coqbot run full CI` after having pushed. |}]

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
