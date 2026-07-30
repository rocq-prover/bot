open Alcotest

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
