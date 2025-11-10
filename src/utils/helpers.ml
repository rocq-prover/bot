open Base
open Bot_components
open Bot_components.Bot_info
open Lwt.Infix
open Lwt.Syntax
open Git_utils
open Utils

let init_git_bare_repository ~bot_info =
  let* () = Lwt_io.printl "Initializing repository..." in
  "git init --bare"
  |&& f {|git config user.email "%s"|} bot_info.email
  |&& f {|git config user.name "%s"|} bot_info.github_name
  |> execute_cmd ~mask:[bot_info.github_pat]
  >>= function
  | Ok _ ->
      Lwt_io.printl "Bare repository initialized."
  | Error e ->
      Lwt_io.printlf "Error while initializing bare repository: %s." e
