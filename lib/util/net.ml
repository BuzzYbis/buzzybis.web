(* Network and external process utilities *)

let run_cmd cmd =
  try
    let ic = Unix.open_process_in cmd in
    let out = In_channel.input_all ic in
    let status = Unix.close_process_in ic in
    Ok (status, out)
  with
  | exn ->
    Error
      (Error.Fs (Error.Fs_read_failed { path = cmd; details = Printexc.to_string exn }))
;;

let http_get url =
  let cmd =
    Printf.sprintf
      "curl -s -H 'User-Agent: BuzzYbis-Fetcher' -H 'Accept: \
       application/vnd.github.v3+json' %s"
      (Filename.quote url)
  in
  match run_cmd cmd with
  | Ok (Unix.WEXITED 0, output) -> Ok output
  | Ok (Unix.WEXITED code, output) ->
    Error (Error.http_failed ~url ~status_code:code output)
  | Ok ((Unix.WSIGNALED _ | Unix.WSTOPPED _), output) ->
    Error (Error.http_failed ~url output)
  | Error err -> Error err
;;

let download_file ~url ~dest =
  let cmd =
    Printf.sprintf "curl -s -L -o %s %s" (Filename.quote dest) (Filename.quote url)
  in
  match run_cmd cmd with
  | Ok (Unix.WEXITED 0, _) -> Ok ()
  | Ok (Unix.WEXITED code, out) ->
    Error
      (Error.download_failed ~url ~dest (Printf.sprintf "curl exit code %d: %s" code out))
  | Ok ((Unix.WSIGNALED _ | Unix.WSTOPPED _), out) ->
    Error (Error.download_failed ~url ~dest out)
  | Error err -> Error err
;;
