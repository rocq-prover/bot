open Bot_components

val handle_minimizer_webhook :
     bot_info:Bot_info.t
  -> key:Mirage_crypto_pk.Rsa.priv
  -> app_id:int
  -> endpoint:string
  -> body:string Lwt.t
  -> (Cohttp.Response.t * Cohttp_lwt__Body.t) Lwt.t
