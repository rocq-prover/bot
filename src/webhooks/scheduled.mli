open Bot_components

val handle_stale_pr_check :
     bot_info:Bot_info.t
  -> key:Mirage_crypto_pk.Rsa.priv
  -> app_id:int
  -> daily_schedule_secret:string
  -> body:string Lwt.t
  -> (Cohttp.Response.t * Cohttp_lwt__Body.t) Lwt.t
