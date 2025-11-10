open Bot_components

val handle_gitlab_webhook :
     bot_info:Bot_info.t
  -> key:Mirage_crypto_pk.Rsa.priv
  -> app_id:int
  -> gitlab_mapping:(string, string) Base.Hashtbl.t
  -> gitlab_webhook_secret:string
  -> headers:Cohttp.Header.t
  -> body:string Lwt.t
  -> (Cohttp.Response.t * Cohttp_lwt__Body.t) Lwt.t
