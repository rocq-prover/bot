open Base
open GitLab_types
open Utils

(******************************************************************************)
(* Pipeline Summary and Error Formatting                                      *)
(******************************************************************************)

let create_pipeline_summary ?summary_top pipeline_info pipeline_url =
  let variables =
    List.map pipeline_info.variables ~f:(fun (key, value) ->
        f "- %s: %s" key value )
    |> String.concat ~sep:"\n"
  in
  let sorted_builds =
    pipeline_info.builds
    |> List.sort ~compare:(fun build1 build2 ->
        String.compare build1.build_name build2.build_name )
  in
  let stage_summary =
    pipeline_info.stages
    |> List.concat_map ~f:(fun stage ->
        sorted_builds
        |> List.filter_map ~f:(fun build ->
            if String.equal build.stage stage then
              Some
                (f "  - [%s](%s/-/jobs/%d)" build.build_name
                   pipeline_info.common_info.http_repo_url build.build_id )
            else None )
        |> List.cons ("- " ^ stage) )
    |> String.concat ~sep:"\n"
  in
  [ f "This [GitLab pipeline](%s) sets the following variables:" pipeline_url
  ; variables
  ; "It contains the following stages and jobs:"
  ; stage_summary
  ; f "GitLab Project ID: %d" pipeline_info.common_info.project_id ]
  |> (match summary_top with Some text -> List.cons text | None -> Fn.id)
  |> String.concat ~sep:"\n\n"
