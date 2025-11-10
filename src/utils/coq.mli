open Bot_components

val git_coq_bug_minimizer :
     bot_info:Bot_info.t
  -> script:string
  -> comment_thread_id:GitHub_ID.t
  -> comment_author:string
  -> owner:string
  -> repo:string
  -> coq_version:string
  -> ocaml_version:string
  -> minimizer_extra_arguments:string list
  -> (unit, string) result Lwt.t

val git_run_ci_minimization :
     bot_info:Bot_info.t
  -> comment_thread_id:GitHub_ID.t
  -> owner:string
  -> repo:string
  -> pr_number:string
  -> docker_image:string
  -> target:string
  -> ci_targets:string list
  -> opam_switch:string
  -> failing_urls:string
  -> passing_urls:string
  -> base:string
  -> head:string
  -> minimizer_extra_arguments:string list
  -> bug_file_name:string option
  -> (unit, string) result Lwt.t
