(* Robust Static File & On-Demand Cached PDF HTTP Server in Pure OCaml *)

open Config
include Util.Syntax
module Fs = Util.Fs
module Net = Util.Net

let mime_type path =
  match Filename.extension path with
  | ".html" | ".htm" -> "text/html; charset=utf-8"
  | ".css" -> "text/css; charset=utf-8"
  | ".js" -> "application/javascript; charset=utf-8"
  | ".json" -> "application/json; charset=utf-8"
  | ".pdf" -> "application/pdf"
  | ".ttf" -> "font/ttf"
  | ".otf" -> "font/otf"
  | ".woff2" -> "font/woff2"
  | ".woff" -> "font/woff"
  | ".png" -> "image/png"
  | ".jpg" | ".jpeg" -> "image/jpeg"
  | ".svg" -> "image/svg+xml"
  | ".webp" -> "image/webp"
  | ".ico" -> "image/x-icon"
  | _ -> "application/octet-stream"
;;

let parse_cached_pdf_uri uri =
  if String.contains uri '\000'
  then None
  else (
    let path = Uri.of_string uri |> Uri.path in
    let parts =
      String.split_on_char '/' path |> List.filter (fun s -> not (String.equal s ""))
    in
    match parts with
    | [ "project"; project_name; "cached_pdf"; pdf_filename ]
    | [ "project"; project_name; "html"; "cached_pdf"; pdf_filename ] ->
      if String.ends_with ~suffix:".pdf" pdf_filename
         && (not (String.contains pdf_filename '/'))
         && not (String.contains project_name '/')
      then (
        let slug = Filename.chop_suffix pdf_filename ".pdf" in
        Some (project_name, slug, pdf_filename))
      else None
    | _ -> None)
;;

let record_pdf_download ~cached_dir ~pdf_filename ~full_path =
  let now = Unix.time () in
  (try Unix.utimes full_path now now with
   | Unix.Unix_error _ -> ());
  let json_path = Filename.concat cached_dir ".downloads.json" in
  let entries =
    if Sys.file_exists json_path
    then (
      try
        match Yojson.Safe.from_file json_path with
        | `Assoc items -> items
        | _ -> []
      with
      | Sys_error _ | Yojson.Json_error _ -> [])
    else []
  in
  let filtered = List.remove_assoc pdf_filename entries in
  let updated = (pdf_filename, `Float now) :: filtered in
  let tmp_path = Printf.sprintf "%s.tmp.%d" json_path (Unix.getpid ()) in
  try
    Yojson.Safe.to_file tmp_path (`Assoc updated);
    Sys.rename tmp_path json_path;
    Ok ()
  with
  | exn ->
    (try Sys.remove tmp_path with
     | Sys_error _ | Unix.Unix_error _ -> ());
    Error (Error.json_write_error ~path:json_path (Printexc.to_string exn))
;;

let compile_cached_pdf ~project_name ~slug ~cached_dir ~full_cached_path =
  let* () = Fs.mkdir_p cached_dir in
  let cwd = Sys.getcwd () in
  let temp_root = Filename.concat "_fetch_tmp" project_name in
  let temp_blog = Filename.concat temp_root "blog" in
  let src_typ = Filename.concat temp_blog (slug ^ ".typ") in
  if not (Sys.file_exists src_typ)
  then (
    Logger.info "[ON-DEMAND COMPILE] Typst source %s not found. Running fetch..." src_typ;
    ignore
      (Net.run_cmd "dune exec --root . -- bin/fetch.exe"
       : (Unix.process_status * string, Error.t) result));
  if not (Sys.file_exists src_typ)
  then Error (Error.typst_source_missing src_typ)
  else (
    let home = Sys.getenv_opt "HOME" |> Option.value ~default:"" in
    let font_dirs =
      [ Filename.concat cwd "site/assets/fonts"
      ; Filename.concat home "Library/Fonts"
      ; "/System/Library/Fonts/Supplemental"
      ; Filename.concat home ".local/share/fonts"
      ; "/usr/share/fonts"
      ; "/usr/local/share/fonts"
      ]
      |> List.filter (fun dir -> (not (String.equal dir "")) && Sys.file_exists dir)
    in
    let font_arg =
      match font_dirs with
      | [] -> ""
      | dirs ->
        let render_flag dir = Printf.sprintf "--font-path %s" (Filename.quote dir) in
        (dirs |> List.map render_flag |> String.concat " ") ^ " "
    in
    let config =
      match Config.load_projects_toml Config.config_file with
      | Ok cfg -> cfg
      | Error _ ->
        { Config.projects_dir = "../buzzybis_projects"
        ; poll_interval = 300
        ; projects = []
        }
    in
    let repo_url =
      match
        List.find_opt
          (fun (p : Config.project) -> String.equal p.name project_name)
          config.projects
      with
      | Some p -> p.repo_url
      | None -> ""
    in
    let tmp_pdf = Printf.sprintf "%s.tmp.%d.pdf" full_cached_path (Unix.getpid ()) in
    let cmd =
      Printf.sprintf
        "typst compile --root %s %s--input repo_url=%s %s %s 2>&1"
        (Filename.quote temp_root)
        font_arg
        (Filename.quote repo_url)
        (Filename.quote src_typ)
        (Filename.quote tmp_pdf)
    in
    Logger.info "[ON-DEMAND COMPILE] Compiling %s to %s ..." src_typ full_cached_path;
    let* status, raw_output = Net.run_cmd cmd in
    match status with
    | Unix.WEXITED 0 ->
      (try
         Sys.rename tmp_pdf full_cached_path;
         Logger.info "[✔] Successfully compiled %s" full_cached_path;
         Ok full_cached_path
       with
       | exn ->
         (try Sys.remove tmp_pdf with
          | Sys_error _ | Unix.Unix_error _ -> ());
         Error (Error.fs_write_failed ~path:full_cached_path (Printexc.to_string exn)))
    | Unix.WEXITED code ->
      (try Sys.remove tmp_pdf with
       | Sys_error _ | Unix.Unix_error _ -> ());
      Error (Error.typst_compile_failed ~src:src_typ ~exit_code:code ~output:raw_output)
    | Unix.WSIGNALED signum ->
      (try Sys.remove tmp_pdf with
       | Sys_error _ | Unix.Unix_error _ -> ());
      Error
        (Error.typst_compile_failed
           ~src:src_typ
           ~exit_code:(128 + signum)
           ~output:raw_output)
    | Unix.WSTOPPED _ ->
      (try Sys.remove tmp_pdf with
       | Sys_error _ | Unix.Unix_error _ -> ());
      Error (Error.typst_compile_failed ~src:src_typ ~exit_code:1 ~output:raw_output))
;;

let is_regular_file path =
  try
    let stats = Unix.stat path in
    stats.Unix.st_kind = Unix.S_REG
  with
  | Unix.Unix_error _ -> false
;;

let sanitize_path uri_path =
  let path = Uri.of_string uri_path |> Uri.path in
  let segments = String.split_on_char '/' path in
  let rec resolve acc = function
    | [] -> Ok (List.rev acc)
    | "" :: rest | "." :: rest -> resolve acc rest
    | ".." :: _ when acc = [] ->
      Error
        (Error.traversal_rejected ~path:uri_path ~reason:"Escaped beyond root via '..'")
    | ".." :: rest -> resolve (List.tl acc) rest
    | seg :: rest -> resolve (seg :: acc) rest
  in
  let* clean_segments = resolve [] segments in
  Ok (String.concat Filename.dir_sep clean_segments)
;;

let is_within_root ~root ~target =
  try
    let canonical_root = Unix.realpath root in
    let canonical_target = Unix.realpath target in
    let root_with_sep =
      if String.ends_with ~suffix:Filename.dir_sep canonical_root
      then canonical_root
      else canonical_root ^ Filename.dir_sep
    in
    if String.equal canonical_target canonical_root
       || String.starts_with ~prefix:root_with_sep canonical_target
    then Ok ()
    else Error (Error.symlink_escape ~root:canonical_root ~target:canonical_target)
  with
  | Unix.Unix_error (err, fn, p) ->
    Error (Error.of_unix_error ~op:Error.Stat ~path:target err fn p)
;;

let resolve_file ~docroot ~uri_path =
  if String.contains uri_path '\000'
  then Error (Error.traversal_rejected ~path:uri_path ~reason:"NUL byte in path rejected")
  else
    let* clean_rel_path = sanitize_path uri_path in
    let target =
      if String.equal clean_rel_path ""
      then docroot
      else Filename.concat docroot clean_rel_path
    in
    let candidate =
      if Sys.file_exists target && Sys.is_directory target
      then (
        let direct_index = Filename.concat target "index.html" in
        let html_index = Filename.concat (Filename.concat target "html") "index.html" in
        if Sys.file_exists direct_index
        then direct_index
        else if Sys.file_exists html_index
        then html_index
        else direct_index)
      else if (not (Sys.file_exists target)) && Sys.file_exists (target ^ ".html")
      then target ^ ".html"
      else target
    in
    if Sys.file_exists candidate && is_regular_file candidate
    then
      let* () = is_within_root ~root:docroot ~target:candidate in
      Ok candidate
    else Error (Error.not_found candidate)
;;

let default_security_headers =
  [ "X-Content-Type-Options", "nosniff"
  ; "X-Frame-Options", "SAMEORIGIN"
  ; "Referrer-Policy", "strict-origin-when-cross-origin"
  ]
;;

let format_headers headers =
  headers |> List.map (fun (k, v) -> Printf.sprintf "%s: %s\r\n" k v) |> String.concat ""
;;

let send_response oc ~status ~content_type ?(headers = []) body =
  let all_headers =
    [ "Content-Type", content_type
    ; "Content-Length", string_of_int (String.length body)
    ; "Connection", "close"
    ]
    @ default_security_headers
    @ headers
  in
  let response =
    Printf.sprintf "HTTP/1.1 %s\r\n%s\r\n%s" status (format_headers all_headers) body
  in
  Out_channel.output_string oc response;
  Out_channel.flush oc
;;

let send_file_headers oc ~status ~content_type ~content_length ?(headers = []) () =
  let all_headers =
    [ "Content-Type", content_type
    ; "Content-Length", string_of_int content_length
    ; "Connection", "close"
    ]
    @ default_security_headers
    @ headers
  in
  let header_str =
    Printf.sprintf "HTTP/1.1 %s\r\n%s\r\n" status (format_headers all_headers)
  in
  Out_channel.output_string oc header_str;
  Out_channel.flush oc
;;

let send_file_body oc path =
  try
    In_channel.with_open_bin path (fun ic ->
      let buf = Bytes.create 65536 in
      let rec loop () =
        let n = In_channel.input ic buf 0 65536 in
        if n > 0
        then (
          Out_channel.output oc buf 0 n;
          loop ())
        else Out_channel.flush oc
      in
      loop ())
  with
  | Sys_error _ | Unix.Unix_error _ -> ()
;;

let handle_client ~docroot ~client_fd =
  let ic = Unix.in_channel_of_descr client_fd in
  let oc = Unix.out_channel_of_descr client_fd in
  (try
     let request_line = In_channel.input_line ic in
     match request_line with
     | None -> ()
     | Some line ->
       let parts = String.split_on_char ' ' line in
       (match parts with
        | (("GET" | "HEAD") as meth) :: uri :: _ ->
          let rec drain_headers () =
            match In_channel.input_line ic with
            | Some h when not (String.equal (String.trim h) "") -> drain_headers ()
            | Some _ | None -> ()
          in
          drain_headers ();
          (match parse_cached_pdf_uri uri with
           | Some (project_name, slug, pdf_filename) ->
             let pdir = Config.get_projects_dir_standalone () in
             let cached_dir =
               Filename.concat
                 (Filename.concat (Filename.concat pdir project_name) "html")
                 "cached_pdf"
             in
             let full_cached_path = Filename.concat cached_dir pdf_filename in
             let available_res =
               if Sys.file_exists full_cached_path
               then Ok full_cached_path
               else compile_cached_pdf ~project_name ~slug ~cached_dir ~full_cached_path
             in
             (match available_res with
              | Ok pdf_path when is_regular_file pdf_path ->
                ignore
                  (record_pdf_download ~cached_dir ~pdf_filename ~full_path:pdf_path
                   : (unit, Error.t) result);
                let len = (Unix.stat pdf_path).Unix.st_size in
                let headers =
                  [ ( "Content-Disposition"
                    , Printf.sprintf "attachment; filename=\"%s\"" pdf_filename )
                  ]
                in
                send_file_headers
                  oc
                  ~status:"200 OK"
                  ~content_type:"application/pdf"
                  ~content_length:len
                  ~headers
                  ();
                if String.equal meth "GET" then send_file_body oc pdf_path
              | Ok _ ->
                let err = Error.not_found full_cached_path in
                Logger.log_error ~context:"handle_client: cached_pdf" err;
                send_response
                  oc
                  ~status:"404 Not Found"
                  ~content_type:"text/plain"
                  "404 Not Found - PDF not found"
              | Error err ->
                Logger.log_error ~context:"handle_client: compile_cached_pdf" err;
                send_response
                  oc
                  ~status:"404 Not Found"
                  ~content_type:"text/plain"
                  "404 Not Found - Unable to compile PDF")
           | None ->
             (match resolve_file ~docroot ~uri_path:uri with
              | Ok filepath ->
                let len = (Unix.stat filepath).Unix.st_size in
                let mime = mime_type filepath in
                send_file_headers
                  oc
                  ~status:"200 OK"
                  ~content_type:mime
                  ~content_length:len
                  ();
                if String.equal meth "GET" then send_file_body oc filepath
              | Error err ->
                Logger.log_error
                  ~context:(Printf.sprintf "handle_client: resolve_file '%s'" uri)
                  err;
                send_response
                  oc
                  ~status:"404 Not Found"
                  ~content_type:"text/plain"
                  "404 Not Found"))
        | _ ->
          let err = Error.server_malformed_request line in
          Logger.log_error ~context:"handle_client" err;
          send_response
            oc
            ~status:"400 Bad Request"
            ~content_type:"text/plain"
            "400 Bad Request")
   with
   | exn ->
     Logger.log_error
       ~context:"handle_client: client_socket"
       (Error.server_socket_error (Printexc.to_string exn)));
  (try Out_channel.close_noerr oc with
   | _ -> ());
  try In_channel.close_noerr ic with
  | _ -> ()
;;

let main () =
  Logger.init ();
  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  let port = if Array.length Sys.argv > 1 then int_of_string Sys.argv.(1) else 8000 in
  let docroot = "build" in
  if not (Sys.file_exists docroot)
  then (
    Logger.error "Directory '%s' does not exist. Run 'make build' first." docroot;
    exit 1);
  let server_sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt server_sock Unix.SO_REUSEADDR true;
  let addr = Unix.ADDR_INET (Unix.inet_addr_any, port) in
  (try Unix.bind server_sock addr with
   | Unix.Unix_error (Unix.EADDRINUSE, _, _) ->
     Logger.log_error
       ~context:"server_init"
       (Error.server_port_in_use
          ~port
          "Port is already in use. Run 'lsof -ti :8000 | xargs kill -9' to free it.");
     exit 1
   | exn ->
     Logger.log_error
       ~context:"server_init"
       (Error.server_socket_error (Printexc.to_string exn));
     exit 1);
  Unix.listen server_sock 128;
  Logger.info "BuzzYbis OCaml HTTP Server listening on http://localhost:%d" port;
  while true do
    try
      let client_sock, (_client_addr : Unix.sockaddr) = Unix.accept server_sock in
      ignore
        (Thread.create (fun () -> handle_client ~docroot ~client_fd:client_sock) ()
         : Thread.t);
      ()
    with
    | Unix.Unix_error (Unix.EINTR, _, _) -> ()
    | exn ->
      Logger.log_error
        ~context:"accept_loop"
        (Error.server_socket_error (Printexc.to_string exn))
  done
;;
