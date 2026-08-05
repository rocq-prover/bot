open Alcotest

let test_link_with_url () =
  check string "with url"
    "[running minimization](https://example.com/minimizer)"
    (Minimization.minimizer_status_link
       ~minimizer_url:(Some "https://example.com/minimizer") ~verb:"running" )

let test_link_without_url () =
  check string "without url" "running minimization"
    (Minimization.minimizer_status_link ~minimizer_url:None ~verb:"running")

let () =
  run "Minimization tests"
    [ ( "minimizer_status_link"
      , [ ("with url", `Quick, test_link_with_url)
        ; ("without url", `Quick, test_link_without_url) ] ) ]
