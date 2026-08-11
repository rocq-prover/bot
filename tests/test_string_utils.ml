open Alcotest
open Base
open String_utils

let test_strip_quoted_bot_name () =
  let input =
    {|>this didn't produce a pipeline for some reason\r\n\r\nI think that this is normal. @herbelin was maybe expecting that adding the `request: full CI` label would trigger a new run immediately, but the semantics is that this label will produce such a full CI run at the next update (next push) of this PR. Cf. the [documentation](https://github.com/coq/coq/blob/master/CONTRIBUTING.md#understanding-automatic-feedback):\r\n\r\n>you can request a full run of the CI by putting the `request: full CI` label before pushing to your PR branch, or by commenting `@coqbot: run full CI` after having pushed. |}
  in
  let expected =
    {|>this didn't produce a pipeline for some reason\r\n\r\nI think that this is normal. @herbelin was maybe expecting that adding the `request: full CI` label would trigger a new run immediately, but the semantics is that this label will produce such a full CI run at the next update (next push) of this PR. Cf. the [documentation](https://github.com/coq/coq/blob/master/CONTRIBUTING.md#understanding-automatic-feedback):\r\n\r\n>you can request a full run of the CI by putting the `request: full CI` label before pushing to your PR branch, or by commenting @`coqbot run full CI` after having pushed. |}
  in
  let got =
    String_utils.strip_quoted_bot_name ~github_bot_name:"coqbot" input
  in
  (check string) "strip_quoted_bot_name" expected got

let () =
  run "String_utils tests"
    [ ( "strip_quoted_bot_name"
      , [test_case "quoted bot name" `Quick test_strip_quoted_bot_name] ) ]

let tokens = Alcotest.list Alcotest.string
let key_values =
  Alcotest.list (Alcotest.pair Alcotest.string (Alcotest.option Alcotest.string))

let check_split ~input ~expected () =
  match split_on_unquoted_whitespace input with
  | Ok actual ->
      Alcotest.check tokens input expected actual
  | Error error ->
      Alcotest.failf "expected %S to parse, but got: %s" input error

let check_split_error ~input ~expected () =
  match split_on_unquoted_whitespace input with
  | Error actual ->
      Alcotest.(check string) input expected actual
  | Ok actual ->
      Alcotest.failf "expected %S to fail, but got: [%s]" input
        (String.concat ~sep:"; " actual)

let check_arguments ~input ~expected () =
  match parse_key_value_arguments input with
  | Ok actual ->
      Alcotest.check key_values input expected actual
  | Error error ->
      Alcotest.failf "expected %S to parse, but got: %s" input error

let check_argument_error ~input ~expected () =
  match parse_key_value_arguments input with
  | Error actual ->
      Alcotest.(check string) input expected actual
  | Ok _ ->
      Alcotest.failf "expected %S to fail" input

let () =
  Alcotest.run "String_utils tests"
    [ ( "split_on_unquoted_whitespace"
      , [ ( "empty input"
          , `Quick
          , check_split ~input:"" ~expected:[] )
        ; ( "unquoted arguments"
          , `Quick
          , check_split ~input:"x=foo y=true" ~expected:["x=foo"; "y=true"] )
        ; ( "double-quoted whitespace"
          , `Quick
          , check_split ~input:{|x="foo bar" y=true|}
              ~expected:[{|x="foo bar"|}; "y=true"] )
        ; ( "single-quoted whitespace"
          , `Quick
          , check_split ~input:"x='foo bar' y=true"
              ~expected:["x='foo bar'"; "y=true"] )
        ; ( "repeated whitespace"
          , `Quick
          , check_split ~input:"  x=foo\t\ty=true  "
              ~expected:["x=foo"; "y=true"] )
        ; ( "escaped quote"
          , `Quick
          , check_split ~input:{|x="foo \"bar\" baz" y=true|}
              ~expected:[{|x="foo \"bar\" baz"|}; "y=true"] )
        ; ( "escaped whitespace"
          , `Quick
          , check_split ~input:{|x=foo\ bar y=true|}
              ~expected:[{|x=foo\ bar|}; "y=true"] )
        ; ( "empty quoted arguments"
          , `Quick
          , check_split ~input:{|"" ''|} ~expected:[{|""|}; "''"] )
        ; ( "unterminated double quote"
          , `Quick
          , check_split_error ~input:{|x="foo bar|}
              ~expected:"unterminated \" quote" )
        ; ( "trailing escape"
          , `Quick
          , check_split_error ~input:{|x=foo\|}
              ~expected:"trailing escape character" ) ] )
    ; ( "parse_key_value_arguments"
      , [ ( "quoted value"
          , `Quick
          , check_arguments ~input:{|x="foo bar" y=true|}
              ~expected:[("x", Some "foo bar"); ("y", Some "true")] )
        ; ( "single-quoted value"
          , `Quick
          , check_arguments ~input:"x='foo bar' y=true"
              ~expected:[("x", Some "foo bar"); ("y", Some "true")] )
        ; ( "concatenated quoted text"
          , `Quick
          , check_arguments ~input:{|x=foo" bar" y='true'|}
              ~expected:[("x", Some "foo bar"); ("y", Some "true")] )
        ; ( "quoted whole argument"
          , `Quick
          , check_arguments ~input:{|"x=foo bar" y=true|}
              ~expected:[("x", Some "foo bar"); ("y", Some "true")] )
        ; ( "escaped whitespace"
          , `Quick
          , check_arguments ~input:{|x=foo\ bar y=true|}
              ~expected:[("x", Some "foo bar"); ("y", Some "true")] )
        ; ( "escaped quote"
          , `Quick
          , check_arguments ~input:{|x="foo \"bar\""|}
              ~expected:[("x", Some {|foo "bar"|})] )
        ; ( "literal nested quotes"
          , `Quick
          , check_arguments ~input:{|x='"foo bar"'|}
              ~expected:[("x", Some {|"foo bar"|})] )
        ; ( "explicit empty values"
          , `Quick
          , check_arguments ~input:{|x= y=""|}
              ~expected:[("x", Some ""); ("y", Some "")] )
        ; ( "additional equal signs"
          , `Quick
          , check_arguments ~input:"x=foo=bar"
              ~expected:[("x", Some "foo=bar")] )
        ; ( "missing value"
          , `Quick
          , check_arguments ~input:"x=foo missing"
              ~expected:[("x", Some "foo"); ("missing", None)] )
        ; ( "empty key"
          , `Quick
          , check_argument_error ~input:"=value"
              ~expected:"argument \"=value\" has an empty key" )
        ; ( "empty quoted key"
          , `Quick
          , check_argument_error ~input:{|""|}
              ~expected:"argument \"\" has an empty key" )
        ; ( "coq_opam_packages"
          , `Quick
          , check_arguments
              ~input:{|coq_opam_packages="a b c" coq_native|}
              ~expected:[("coq_opam_packages", Some "a b c"); ("coq_native", None)])
        ] ) ]
