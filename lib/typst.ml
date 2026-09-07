(* Typst compiler invocation. *)

let font_dirs () =
  let home = Sys.getenv_opt "HOME" |> Option.value ~default:"" in
  [ Filename.concat (Sys.getcwd ()) "site/assets/fonts"
  ; Filename.concat home "Library/Fonts"
  ; "/System/Library/Fonts/Supplemental"
  ; Filename.concat home ".local/share/fonts"
  ; "/usr/share/fonts"
  ; "/usr/local/share/fonts"
  ]
  |> List.filter (fun dir -> (not (String.equal dir "")) && Sys.file_exists dir)
;;

let compile ~root ~inputs ?(args = []) ~src ~output () =
  let argv =
    [ "compile"; "--root"; root ]
    @ List.concat_map (fun dir -> [ "--font-path"; dir ]) (font_dirs ())
    @ List.concat_map (fun (key, value) -> [ "--input"; key ^ "=" ^ value ]) inputs
    @ args
    @ [ src; output ]
  in
  match Util.Proc.run "typst" argv with
  | Error _ as err -> err
  | Ok out when Util.Proc.succeeded out.status -> Ok out.stdout
  | Ok out ->
    Error
      (Error.typst_compile_failed
         ~src
         ~exit_code:(Util.Proc.exit_code out.status)
         (String.trim out.stderr))
;;

let compile_html ~root ~repo_url ~src =
  compile
    ~root
    ~inputs:[ "repo_url", repo_url; "format", "html" ]
    ~args:[ "--features"; "html"; "-f"; "html" ]
    ~src
    ~output:"-"
    ()
;;

let compile_pdf ~root ~repo_url ~src ~output =
  match compile ~root ~inputs:[ "repo_url", repo_url ] ~src ~output () with
  | Ok (_ : string) -> Ok ()
  | Error _ as err -> err
;;
