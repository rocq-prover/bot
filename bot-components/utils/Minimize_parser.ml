open Base
open String_utils
open Utils

(******************************************************************************)
(* Types                                                                      *)
(******************************************************************************)

type minimize_parsed =
  | MinimizeScript of {quote_kind: string; body: string}
  | MinimizeAttachment of {description: string; url: string}

(******************************************************************************)
(* Helper Extraction Functions                                                *)
(******************************************************************************)

let extract_minimize_file body =
  match Str.split (Str.regexp_string "\n```") body with
  | hd :: _ ->
      hd
  | [] ->
      ""

let extract_minimize_script quote_kind body =
  MinimizeScript
    { quote_kind= quote_kind |> Str.global_replace (Str.regexp "[ \r]") ""
    ; body= body |> extract_minimize_file }

let extract_minimize_url url =
  url |> Str.global_replace (Str.regexp "^[` ]+\\|[` ]+$") ""

let extract_minimize_attachment ?(description = "") url =
  MinimizeAttachment {description; url= url |> extract_minimize_url}

(******************************************************************************)
(* Request Parsing Utilities                                                  *)
(******************************************************************************)

let parse_minimiation_requests requests =
  requests
  |> Str.global_replace (Str.regexp "[ ,]+") " "
  |> Stdlib.String.split_on_char ' '
  |> List.map ~f:Stdlib.String.trim
  (* remove trailing : in case the user stuck a : at the end of the line *)
  |> List.map ~f:(Str.global_replace (Str.regexp ":$") "")
  |> List.filter ~f:(fun r -> String.length r <> 0)

(******************************************************************************)
(* Minimize Request Parsers                                                   *)
(******************************************************************************)

let parse_minimize_text_of_body ~github_bot_name body =
  if
    string_match
      ~regexp:
        ( f
            "@%s:? [Mm]inimize\\([^`]*\\)```\\([^\n\
             \r]*\\)[\r]*\n\
             \\(\\(.\\|\n\
             \\)+\\)"
        @@ Str.quote github_bot_name )
      body
  then
    (* avoid internal server errors from unclear execution order *)
    let options, quote_kind, body =
      ( Str.matched_group 1 body
      , Str.matched_group 2 body
      , Str.matched_group 3 body )
    in
    Some (options, extract_minimize_script quote_kind body)
  else if
    string_match
      ~regexp:
        ( f "@%s? [Mm]inimize\\([^`]*\\)\\[\\([^]]*\\)\\] *(\\([^)]*\\))"
        @@ Str.quote github_bot_name )
      body
  then
    (* avoid internal server errors from unclear execution order *)
    let options, description, url =
      ( Str.matched_group 1 body
      , Str.matched_group 2 body
      , Str.matched_group 3 body )
    in
    Some (options, extract_minimize_attachment ~description url)
  else None

(******************************************************************************)
(* CI Minimize Request Parsers                                                *)
(******************************************************************************)

let parse_ci_minimize_text_of_body ~github_bot_name body =
  if
    string_match
      ~regexp:
        ( f "@%s:?\\( [^\n]*\\)\\b[Cc][Ii][- ][Mm]inimize:?\\([^\n]*\\)"
        @@ Str.quote github_bot_name )
      body
  then
    let options = Str.matched_group 1 body in
    let requests = Str.matched_group 2 body in
    Some (options, requests |> parse_minimiation_requests)
  else None

let parse_resume_ci_minimize_text_of_body ~github_bot_name body =
  if
    string_match
      ~regexp:
        ( f
            "@%s:?\\( [^\n\
             ] *\\)\\bresume [Cc][Ii][- ][Mm]inimiz\\(e\\|ation\\):?\\([^\n\
             ]*\\)[\r]*\n\
             +```\\([^\n\
             ]*\\)[\r]*\n\
             \\(\\(.\\|\n\
             \\)+\\)"
        @@ Str.quote github_bot_name )
      body
  then
    let options, requests, quote_kind, body =
      ( Str.matched_group 1 body
      , Str.matched_group 3 body
      , Str.matched_group 4 body
      , Str.matched_group 5 body )
    in
    Some
      ( options
      , requests |> parse_minimiation_requests
      , extract_minimize_script quote_kind body )
  else if
    string_match
      ~regexp:
        ( f
            "@%s:?\\( [^\n\
             ]*\\)\\bresume [Cc][Ii][- ][Mm]inimiz\\(e\\|ation\\):?[ \n\
            \            ]+\\([^ \n\
            \            ]+\\)[ \n\
            \            ]+\\[\\([^]]*\\)\\] *(\\([^)]*\\))"
        @@ Str.quote github_bot_name )
      body
  then
    let options, requests, description, url =
      ( Str.matched_group 1 body
      , Str.matched_group 3 body
      , Str.matched_group 4 body
      , Str.matched_group 5 body )
    in
    Some
      ( options
      , requests |> parse_minimiation_requests
      , extract_minimize_attachment ~description url )
  else if
    string_match
      ~regexp:
        ( f
            "@%s:?\\( [^\n\
             ]*\\)\\bresume [Cc][Ii][- ][Mm]inimiz\\(e\\|ation\\):?[ \n\
            \            ]+\\([^ \n\
            \            ]+\\)[ \n\
            \            ]+\\(https?://[^ \n\
            \            ]+\\)"
        @@ Str.quote github_bot_name )
      body
  then
    let options, requests, url =
      ( Str.matched_group 1 body
      , Str.matched_group 3 body
      , Str.matched_group 4 body )
    in
    Some
      ( options
      , requests |> parse_minimiation_requests
      , extract_minimize_attachment url )
  else None

(******************************************************************************)
(* Check Run Parsing                                                          *)
(******************************************************************************)

let parse_check_run_external_id external_id =
  match String.split ~on:',' external_id with
  | [http_repo_url; url_part] -> (
    match Git_utils.parse_gitlab_repo_url ~http_repo_url with
    | Error _ ->
        None
    | Ok (gitlab_domain, _) ->
        Some (gitlab_domain, url_part) )
  | [url_part] ->
      (* Backward compatibility *)
      Some ("gitlab.com", url_part)
  | _ ->
      None
