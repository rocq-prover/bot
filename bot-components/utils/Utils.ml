open Base
open Lwt.Infix
open GitHub_types

let f = Printf.sprintf

let toml_of_string s = Toml.Parser.(from_string s |> unsafe)

let toml_of_file file_path = Toml.Parser.(from_filename file_path |> unsafe)

let subkey_value toml_table k k' =
  Toml.Lenses.(get toml_table (key k |-- table |-- key k' |-- string))

let subkey_table toml_table k k' =
  Toml.Lenses.(get toml_table (key k |-- table |-- key k' |-- table))

let subkey_int toml_table k k' =
  match Toml.Lenses.(get toml_table (key k |-- table |-- key k' |-- int)) with
  | Some n ->
      Some n
  | None ->
      subkey_value toml_table k k' |> Option.map ~f:Int.of_string

let key_value toml_table k = Toml.Lenses.(get toml_table (key k |-- string))

let key_array toml_table k =
  Toml.Lenses.(get toml_table (key k |-- array |-- strings))

let key_bool toml_table k =
  match Toml.Lenses.(get toml_table (key k |-- bool)) with
  | Some b ->
      Some b
  | None ->
      key_value toml_table k |> Option.map ~f:Bool.of_string

let find k toml_table =
  Toml.Types.Table.find (Toml.Types.Table.Key.of_string k) toml_table

let list_table_keys toml_table =
  Toml.Types.Table.fold
    (fun k _ ks -> Toml.Types.Table.Key.to_string k :: ks)
    toml_table []

let days_elapsed ts =
  (* Yes, I know this is wrong because of DST and black holes but it should
     still be correct enough *)
  Float.to_int ((Unix.time () -. ts) /. (3600. *. 24.))

let rec apply_throttle len action args =
  if List.is_empty args || len <= 0 then Lwt.return_unit
  else
    let args, rem = List.split_n args len in
    Lwt_list.map_p action args
    >>= fun ans ->
    let n = List.count ~f:(fun b -> b) ans in
    apply_throttle (len - n) action rem

let report_on_posting_comment = function
  | Ok url ->
      Lwt_io.printf "Posted a new comment: %s\n" url
  | Error f ->
      Lwt_io.printf "Error while posting a comment: %s\n" f

let extract_backport_info ~(bot_info : Bot_info.t) ~description :
    backport_info list =
  let main_regexp =
    "backport to \\([^ ]*\\) (.*move rejected PRs to: "
    ^ "https://github.com/[^/]*/[^/]*/milestone/\\([0-9]+\\)" ^ ")"
  in
  let begin_regexp = bot_info.github_name ^ ": \\(.*\\)$" in
  let backport_info_unit = main_regexp ^ "; \\(.*\\)$" in
  let end_regexp = main_regexp in
  let rec aux description =
    if String_utils.string_match ~regexp:backport_info_unit description then
      let backport_to = Str.matched_group 1 description in
      let rejected_milestone =
        Str.matched_group 2 description |> Int.of_string
      in
      Str.matched_group 3 description
      |> aux
      |> List.cons {backport_to; rejected_milestone}
    else if String_utils.string_match ~regexp:end_regexp description then
      let backport_to = Str.matched_group 1 description in
      let rejected_milestone =
        Str.matched_group 2 description |> Int.of_string
      in
      [{backport_to; rejected_milestone}]
    else []
  in
  if String_utils.string_match ~regexp:begin_regexp description then
    Str.matched_group 1 description |> aux
  else []
