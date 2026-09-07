(* HTTP helpers on top of curl. *)

let curl_args =
  [ "--silent"
  ; "--show-error"
  ; "--location"
  ; "--max-time"
  ; "120"
  ; "--proto"
  ; "=https"
  ; "--proto-redir"
  ; "=https"
  ]
;;

let http_get url =
  let args =
    curl_args
    @ [ "--header"
      ; "User-Agent: BuzzYbis-Fetcher"
      ; "--header"
      ; "Accept: application/vnd.github.v3+json"
      ; "--"
      ; url
      ]
  in
  match Proc.run "curl" args with
  | Error _ as err -> err
  | Ok output when Proc.succeeded output.status -> Ok output.stdout
  | Ok output ->
    Error
      (Error.http_failed
         ~url
         ~exit_code:(Proc.exit_code output.status)
         (String.trim output.stderr))
;;

let download_file ~url ~dest =
  let part = dest ^ ".part" in
  let discard_part () =
    try Sys.remove part with
    | Sys_error _ -> ()
  in
  match Proc.run "curl" (curl_args @ [ "--fail"; "--output"; part; "--"; url ]) with
  | Error err ->
    discard_part ();
    Error err
  | Ok output when Proc.succeeded output.status ->
    (match Sys.rename part dest with
     | () -> Ok ()
     | exception Sys_error msg ->
       discard_part ();
       Error (Error.download_failed ~url ~dest msg))
  | Ok output ->
    discard_part ();
    Error
      (Error.download_failed
         ~url
         ~dest
         (Printf.sprintf
            "curl exit code %d: %s"
            (Proc.exit_code output.status)
            (String.trim output.stderr)))
;;
