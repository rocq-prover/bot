open Base
open GitHub_types
open Lwt.Infix
open Lwt.Syntax
open Utils

let report_status ?(mask = []) ?(stderr_content = "") command report code =
  let stderr =
    if String.is_empty stderr_content then "" else stderr_content ^ "\n"
  in
  Error
    (List.fold_left
       ~init:(f {|Command "%s" %s %d%s%s|} command report code "\n" stderr)
       ~f:(fun acc m -> Str.global_replace (Str.regexp_string m) "XXXXX" acc)
       mask )

let ( |&& ) command1 command2 = command1 ^ " && " ^ command2

let execute_cmd ?(mask = []) command =
  Lwt_io.printf "Executing command: %s\n" command
  >>= fun () ->
  let process = Lwt_process.open_process_full (Lwt_process.shell command) in
  let stdout_pipe =
    HTTP_utils.copy_stream ~src:process#stdout ~dst:Lwt_io.stdout
  in
  let stderr_pipe =
    HTTP_utils.copy_stream ~src:process#stderr ~dst:Lwt_io.stderr
  in
  (* Capture stdout and stderr in parallel *)
  (* Wait for the process to finish *)
  let+ _stdout_content = stdout_pipe
  and+ stderr_content = stderr_pipe
  and+ status = process#status in
  match status with
  | Unix.WEXITED code ->
      if Int.equal code 0 then Ok ()
      else report_status ~mask ~stderr_content command "exited with status" code
  | Unix.WSIGNALED signal ->
      report_status ~mask command "was killed by signal number" signal
  | Unix.WSTOPPED signal ->
      report_status ~mask command "was stopped by signal number" signal

let git_fetch ?(force = true) remote_ref local_branch_name =
  f "git fetch --quiet -fu %s %s%s:%s" remote_ref.repo_url
    (if force then "+" else "")
    (Stdlib.Filename.quote remote_ref.name)
    (Stdlib.Filename.quote local_branch_name)

let git_push ?(force = true) ?(options = "") ~remote_ref ~local_ref () =
  f "git push %s %s%s:%s %s" remote_ref.repo_url
    (if force then " +" else " ")
    (Stdlib.Filename.quote local_ref)
    (Stdlib.Filename.quote remote_ref.name)
    options

let git_delete ~remote_ref = git_push ~force:false ~remote_ref ~local_ref:"" ()

let git_make_ancestor ~pr_title ~pr_number ~base head =
  f "./make_ancestor.sh %s %s %s %d"
    (Stdlib.Filename.quote base)
    (Stdlib.Filename.quote head)
    (Stdlib.Filename.quote pr_title)
    pr_number
  |> Lwt_unix.system
  >|= fun status ->
  match status with
  | Unix.WEXITED 0 ->
      Ok true (* merge successful *)
  | Unix.WEXITED 10 ->
      Ok false (* merge unsuccessful *)
  | Unix.WEXITED code ->
      Error (f "git_make_ancestor script exited with status %d." code)
  | Unix.WSIGNALED signal ->
      Error (f "git_make_ancestor script killed by signal %d." signal)
  | Unix.WSTOPPED signal ->
      Error (f "git_make_ancestor script stopped by signal %d." signal)

let git_test_modified ~base ~head pattern =
  let command =
    f {|git diff %s...%s --name-only | grep "%s"|} base head pattern
  in
  Lwt_unix.system command
  >|= fun status ->
  match status with
  | Unix.WEXITED 0 ->
      Ok true (* file was modified *)
  | Unix.WEXITED 1 ->
      Ok false (* file was not modified *)
  | Unix.WEXITED code ->
      Error (f "%s exited with status %d." command code)
  | Unix.WSIGNALED signal ->
      Error (f "%s killed by signal %d." command signal)
  | Unix.WSTOPPED signal ->
      Error (f "%s stopped by signal %d." command signal)

let pr_from_branch branch =
  if String_utils.string_match ~regexp:"^pr-\\([0-9]*\\)$" branch then
    (Some (Str.matched_group 1 branch |> Int.of_string), "pull request")
  else (None, "branch")

let parse_gitlab_repo_url ~http_repo_url =
  if
    not
      (String_utils.string_match ~regexp:"https?://\\([^/]*\\)/\\(.*/.*\\)"
         http_repo_url )
  then
    Result.Error (f "Could not parse GitLab repository URL %s." http_repo_url)
  else
    Result.Ok
      (Str.matched_group 1 http_repo_url, Str.matched_group 2 http_repo_url)

let parse_gitlab_repo_url_and_print ~http_repo_url =
  match parse_gitlab_repo_url ~http_repo_url with
  | Ok (gitlab_domain, gitlab_repo_full_name) ->
      Stdio.printf "GitLab domain: \"%s\"\n" gitlab_domain ;
      Stdio.printf "GitLab repository full name: \"%s\"\n" gitlab_repo_full_name
  | Error msg ->
      Stdio.print_endline msg

let%expect_test "http_repo_url_parsing_coq" =
  parse_gitlab_repo_url_and_print ~http_repo_url:"https://gitlab.com/coq/coq" ;
  [%expect
    {|
   GitLab domain: "gitlab.com"
   GitLab repository full name: "coq/coq" |}]

let%expect_test "http_repo_url_parsing_mathcomp" =
  parse_gitlab_repo_url_and_print
    ~http_repo_url:"https://gitlab.inria.fr/math-comp/math-comp" ;
  [%expect
    {|
  GitLab domain: "gitlab.inria.fr"
  GitLab repository full name: "math-comp/math-comp" |}]

let%expect_test "http_repo_url_parsing_example_from_gitlab_docs" =
  parse_gitlab_repo_url_and_print
    ~http_repo_url:"https://gitlab.example.com/gitlab-org/gitlab-test" ;
  [%expect
    {|
  GitLab domain: "gitlab.example.com"
  GitLab repository full name: "gitlab-org/gitlab-test" |}]

let init_git_bare_repository ~bot_info =
  let* () = Lwt_io.printl "Initializing repository..." in
  let github_token = Bot_info.github_token bot_info in
  "git init --bare"
  |&& f {|git config user.email "%s"|} bot_info.email
  |&& f {|git config user.name "%s"|} bot_info.github_name
  |> execute_cmd ~mask:[github_token]
  >>= function
  | Ok _ ->
      Lwt_io.printl "Bare repository initialized."
  | Error e ->
      Lwt_io.printlf "Error while initializing bare repository: %s." e
