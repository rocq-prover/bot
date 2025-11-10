open Base
open Bot_components
open Bot_components.Bot_info
open Git_utils

let git_coq_bug_minimizer ~bot_info ~script ~comment_thread_id ~comment_author
    ~owner ~repo ~coq_version ~ocaml_version ~minimizer_extra_arguments =
  (* To push a new branch we need to identify as coqbot the GitHub
     user, who is a collaborator on the run-coq-bug-minimizer repo,
     not coqbot the GitHub App *)
  Stdlib.Filename.quote_command "./coq_bug_minimizer.sh"
    [ script
    ; GitHub_ID.to_string comment_thread_id
    ; comment_author
    ; bot_info.github_pat
    ; bot_info.github_name
    ; bot_info.domain
    ; owner
    ; repo
    ; coq_version
    ; ocaml_version
    ; String.concat ~sep:" " minimizer_extra_arguments ]
  |> execute_cmd ~mask:[bot_info.github_pat]

let git_run_ci_minimization ~bot_info ~comment_thread_id ~owner ~repo ~pr_number
    ~docker_image ~target ~ci_targets ~opam_switch ~failing_urls ~passing_urls
    ~base ~head ~minimizer_extra_arguments ~bug_file_name =
  (* To push a new branch we need to identify as coqbot the GitHub
     user, who is a collaborator on the run-coq-bug-minimizer repo,
     not coqbot the GitHub App *)
  ( [ GitHub_ID.to_string comment_thread_id
    ; bot_info.github_pat
    ; bot_info.github_name
    ; bot_info.domain
    ; owner
    ; repo
    ; pr_number
    ; docker_image
    ; target
    ; String.concat ~sep:" " ci_targets
    ; opam_switch
    ; failing_urls
    ; passing_urls
    ; base
    ; head
    ; String.concat ~sep:" " minimizer_extra_arguments ]
  @
  match bug_file_name with Some bug_file_name -> [bug_file_name] | None -> [] )
  |> Stdlib.Filename.quote_command "./run_ci_minimization.sh"
  |> execute_cmd ~mask:[bot_info.github_pat]
