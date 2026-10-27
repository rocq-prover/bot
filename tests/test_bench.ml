open Alcotest

let args = list (pair string (option string))

let parse_result = option (result args string)

let check_parse ~body ~expected () =
  check parse_result body expected (Bench.parse ~github_bot_name:"coqbot" body)

let () =
  run "Bench parser tests"
    [ ( "parse"
      , [ ( "command without arguments"
          , `Quick
          , check_parse ~body:"@coqbot bench" ~expected:(Some (Ok [])) )
        ; ( "arguments through end of comment"
          , `Quick
          , check_parse
              ~body:"@coqbot bench coq_native\ncoq_opam_packages=\"a b\""
              ~expected:
                (Some
                   (Ok [("coq_native", None); ("coq_opam_packages", Some "a b")])
                ) )
        ; ( "multiline arguments until empty line"
          , `Quick
          , check_parse
              ~body:
                "@coqbot: Bench coq_native=yes\n\
                 coq_opam_packages='a b'\n\n\
                 This text is not part of the command."
              ~expected:
                (Some
                   (Ok
                      [ ("coq_native", Some "yes")
                      ; ("coq_opam_packages", Some "a b") ] ) ) )
        ; ( "malformed arguments"
          , `Quick
          , check_parse ~body:"@coqbot bench value=\"unterminated"
              ~expected:
                (Some
                   (Error
                      "bench command could not parse key-value arguments: \
                       unterminated \" quote" ) ) )
        ; ( "another command"
          , `Quick
          , check_parse ~body:"@coqbot benchmark" ~expected:None ) ] ) ]
