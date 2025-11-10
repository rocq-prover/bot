open Bot_components

val handle_github_webhook :
     bot_info:Bot_info.t
  -> key:Mirage_crypto_pk.Rsa.priv
  -> app_id:int
  -> github_bot_name:string
  -> gitlab_mapping:(string, string) Base.Hashtbl.t
  -> github_mapping:(string, string * string) Base.Hashtbl.t
  -> github_webhook_secret:string
  -> headers:Cohttp.Header.t
  -> body:string Lwt.t
  -> minimize_text_of_body:
       (string -> (string * Minimize_parser.minimize_parsed) option)
  -> ci_minimize_text_of_body:(string -> (string * string list) option)
  -> resume_ci_minimize_text_of_body:
       (   string
        -> (string * string list * Minimize_parser.minimize_parsed) option )
  -> (Cohttp.Response.t * Cohttp_lwt__Body.t) Lwt.t
