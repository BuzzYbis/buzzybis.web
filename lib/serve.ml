(* Static file server with on-demand compilation of cached article PDFs. *)

open Util.Syntax
module Fs = Util.Fs
module Proc = Util.Proc

let docroot = "build"
let default_port = 8000
let max_request_line_bytes = 8 * 1024
let max_header_bytes = 32 * 1024
let socket_timeout_seconds = 15.0
let io_buffer_size = 64 * 1024

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

(* ---- Cached PDF route ---- *)

type pdf_route =
  { project_name : string
  ; slug : string
  ; pdf_filename : string
  }

(* /project/<name>/cached_pdf/<slug>.pdf or /project/<name>/html/cached_pdf/<slug>.pdf.
   Every segment used to build filesystem paths must be a safe name. *)
let parse_pdf_route path =
  let segments =
    String.split_on_char '/' path |> List.filter (fun s -> not (String.equal s ""))
  in
  match segments with
  | [ "project"; project_name; "cached_pdf"; pdf_filename ]
  | [ "project"; project_name; "html"; "cached_pdf"; pdf_filename ]
    when String.ends_with ~suffix:".pdf" pdf_filename ->
    let slug = Filename.chop_suffix pdf_filename ".pdf" in
    if Fs.is_safe_name project_name && Fs.is_safe_name slug
    then Some { project_name; slug; pdf_filename }
    else None
  | _ -> None
;;

let compile_lock = Mutex.create ()
let downloads_lock = Mutex.create ()

let record_pdf_download ~cached_dir ~pdf_filename ~full_path =
  Mutex.protect downloads_lock (fun () ->
    let now = Unix.time () in
    (try Unix.utimes full_path now now with
     | Unix.Unix_error _ -> ());
    let json_path = Filename.concat cached_dir ".downloads.json" in
    let entries =
      (pdf_filename, `Float now)
      :: List.remove_assoc pdf_filename (Fs.read_json_assoc json_path)
    in
    Fs.write_json ~path:json_path (`Assoc entries))
;;

let compile_cached_pdf ~(project : Config.project) ~route ~cached_dir ~full_cached_path =
  Mutex.protect compile_lock (fun () ->
    (* Another request may have compiled it while we waited for the lock. *)
    if Sys.file_exists full_cached_path
    then Ok full_cached_path
    else
      let* () = Fs.mkdir_p cached_dir in
      let temp_root = Filename.concat Config.fetch_tmp_dir route.project_name in
      let src_typ =
        Filename.concat (Filename.concat temp_root "blog") (route.slug ^ ".typ")
      in
      if not (Sys.file_exists src_typ)
      then (
        Logger.info
          "[ON-DEMAND COMPILE] Typst source %s not found. Running fetch..."
          src_typ;
        match
          Proc.run_checked "dune" [ "exec"; "--root"; "."; "--"; "bin/fetch.exe" ]
        with
        | Ok (_ : Proc.output) -> ()
        | Error err -> Logger.log_error ~context:"on-demand fetch" err);
      if not (Sys.file_exists src_typ)
      then Error (Error.typst_source_missing src_typ)
      else (
        let tmp_pdf = Printf.sprintf "%s.tmp.%d.pdf" full_cached_path (Unix.getpid ()) in
        Logger.info "[ON-DEMAND COMPILE] Compiling %s to %s ..." src_typ full_cached_path;
        let result =
          let* () =
            Typst.compile_pdf
              ~root:temp_root
              ~repo_url:project.repo_url
              ~src:src_typ
              ~output:tmp_pdf
          in
          match Sys.rename tmp_pdf full_cached_path with
          | () ->
            Logger.info "[✔] Successfully compiled %s" full_cached_path;
            Ok full_cached_path
          | exception Sys_error msg ->
            Error (Error.fs_write_failed ~path:full_cached_path msg)
        in
        if Result.is_error result then Fs.remove_noerr tmp_pdf;
        result))
;;

(* ---- Static file resolution ---- *)

(* Collapse "." and ".." segments; refuse to climb above the root. *)
let normalize_path path =
  let rec go acc = function
    | [] -> Ok (List.rev acc)
    | ("" | ".") :: rest -> go acc rest
    | ".." :: rest ->
      (match acc with
       | [] ->
         Error (Error.traversal_rejected ~path ~reason:"Escaped beyond root via '..'")
       | _ :: parent -> go parent rest)
    | segment :: rest -> go (segment :: acc) rest
  in
  let+ segments = go [] (String.split_on_char '/' path) in
  String.concat Filename.dir_sep segments
;;

let is_within_root ~root ~target =
  match Unix.realpath root, Unix.realpath target with
  | canonical_root, canonical_target ->
    let root_prefix =
      if String.ends_with ~suffix:Filename.dir_sep canonical_root
      then canonical_root
      else canonical_root ^ Filename.dir_sep
    in
    if
      String.equal canonical_target canonical_root
      || String.starts_with ~prefix:root_prefix canonical_target
    then Ok ()
    else Error (Error.symlink_escape ~root:canonical_root ~target:canonical_target)
  | exception (Unix.Unix_error _ as exn) ->
    Error (Error.of_exn ~op:Error.Stat ~path:target exn)
;;

let resolve_file ~docroot path =
  let* relative = normalize_path path in
  let target =
    if String.equal relative "" then docroot else Filename.concat docroot relative
  in
  let candidate =
    if Fs.is_directory target
    then (
      let direct_index = Filename.concat target "index.html" in
      let nested_index = Filename.concat (Filename.concat target "html") "index.html" in
      if Sys.file_exists direct_index
      then direct_index
      else if Sys.file_exists nested_index
      then nested_index
      else direct_index)
    else if (not (Sys.file_exists target)) && Sys.file_exists (target ^ ".html")
    then target ^ ".html"
    else target
  in
  if Fs.is_regular_file candidate
  then
    let+ () = is_within_root ~root:docroot ~target:candidate in
    candidate
  else Error (Error.not_found candidate)
;;

(* ---- HTTP plumbing ---- *)

type meth =
  | Get
  | Head

type request =
  { meth : meth
  ; target : string
  }

let security_headers =
  [ "X-Content-Type-Options", "nosniff"
  ; "X-Frame-Options", "SAMEORIGIN"
  ; "Referrer-Policy", "strict-origin-when-cross-origin"
  ]
;;

let send_head oc ~status ~content_type ~content_length ?(extra = []) () =
  let headers =
    [ "Content-Type", content_type
    ; "Content-Length", string_of_int content_length
    ; "Connection", "close"
    ]
    @ security_headers
    @ extra
  in
  Out_channel.output_string oc (Printf.sprintf "HTTP/1.1 %s\r\n" status);
  List.iter
    (fun (name, value) ->
       Out_channel.output_string oc (Printf.sprintf "%s: %s\r\n" name value))
    headers;
  Out_channel.output_string oc "\r\n"
;;

let respond_text oc ~meth ~status body =
  send_head
    oc
    ~status
    ~content_type:"text/plain; charset=utf-8"
    ~content_length:(String.length body)
    ();
  (match meth with
   | Get -> Out_channel.output_string oc body
   | Head -> ());
  Out_channel.flush oc
;;

let copy_file_to oc path =
  In_channel.with_open_bin path (fun ic ->
    let buf = Bytes.create io_buffer_size in
    let rec loop () =
      match In_channel.input ic buf 0 io_buffer_size with
      | 0 -> ()
      | n ->
        Out_channel.output oc buf 0 n;
        loop ()
    in
    loop ())
;;

let respond_file oc ~meth ?(extra = []) path =
  match (Unix.stat path).Unix.st_size with
  | content_length ->
    send_head oc ~status:"200 OK" ~content_type:(mime_type path) ~content_length ~extra ();
    (match meth with
     | Get -> copy_file_to oc path
     | Head -> ());
    Out_channel.flush oc
  | exception Unix.Unix_error _ ->
    Logger.log_error ~context:"respond_file" (Error.not_found path);
    respond_text oc ~meth ~status:"404 Not Found" "404 Not Found"
;;

(* Read one CRLF/LF-terminated line without ever buffering more than [limit] bytes. *)
let read_line_bounded ic ~limit =
  let buf = Buffer.create 256 in
  let rec go () =
    if Buffer.length buf > limit
    then `Too_long
    else (
      match In_channel.input_char ic with
      | None -> if Buffer.length buf = 0 then `Eof else `Line (Buffer.contents buf)
      | Some '\n' -> `Line (Buffer.contents buf)
      | Some c ->
        Buffer.add_char buf c;
        go ())
  in
  go ()
;;

(* Skip the header block, enforcing an overall size budget. *)
let drain_headers ic =
  let rec go remaining =
    if remaining < 0
    then Error "431 Request Header Fields Too Large"
    else (
      match read_line_bounded ic ~limit:remaining with
      | `Too_long -> Error "431 Request Header Fields Too Large"
      | `Eof -> Ok ()
      | `Line line when String.equal (String.trim line) "" -> Ok ()
      | `Line line -> go (remaining - String.length line - 1))
  in
  go max_header_bytes
;;

let is_valid_target target =
  String.starts_with ~prefix:"/" target
  && String.for_all (fun c -> Char.code c > 32 && Char.code c <> 127) target
;;

let read_request ic =
  match read_line_bounded ic ~limit:max_request_line_bytes with
  | `Eof -> Ok None
  | `Too_long -> Error "414 URI Too Long"
  | `Line line ->
    let* () = drain_headers ic in
    (match String.split_on_char ' ' (String.trim line) with
     | (("GET" | "HEAD") as m) :: target :: _ when is_valid_target target ->
       Ok (Some { meth = (if String.equal m "GET" then Get else Head); target })
     | _ -> Error "400 Bad Request")
;;

(* ---- Request handling ---- *)

let serve_cached_pdf oc ~meth ~config ~(project : Config.project) route =
  let paths = Config.project_paths config project in
  let cached_dir = paths.cached_pdf_dir in
  let full_cached_path = Filename.concat cached_dir route.pdf_filename in
  let available =
    if Sys.file_exists full_cached_path
    then Ok full_cached_path
    else compile_cached_pdf ~project ~route ~cached_dir ~full_cached_path
  in
  match available with
  | Ok pdf_path when Fs.is_regular_file pdf_path ->
    Logger.report
      ~context:"record_pdf_download"
      (record_pdf_download
         ~cached_dir
         ~pdf_filename:route.pdf_filename
         ~full_path:pdf_path);
    let extra =
      [ ( "Content-Disposition"
        , Printf.sprintf "attachment; filename=\"%s\"" route.pdf_filename )
      ]
    in
    respond_file oc ~meth ~extra pdf_path
  | Ok pdf_path ->
    Logger.log_error ~context:"serve_cached_pdf" (Error.not_found pdf_path);
    respond_text oc ~meth ~status:"404 Not Found" "404 Not Found - PDF not found"
  | Error err ->
    Logger.log_error ~context:"compile_cached_pdf" err;
    respond_text oc ~meth ~status:"404 Not Found" "404 Not Found - Unable to compile PDF"
;;

let serve_static oc ~meth ~target path =
  match resolve_file ~docroot path with
  | Ok file_path -> respond_file oc ~meth file_path
  | Error err ->
    Logger.log_error ~context:(Printf.sprintf "resolve_file '%s'" target) err;
    respond_text oc ~meth ~status:"404 Not Found" "404 Not Found"
;;

let handle_request oc ~config { meth; target } =
  let path = Uri.path (Uri.of_string target) in
  let pdf_project =
    Option.bind (parse_pdf_route path) (fun route ->
      Option.map
        (fun project -> project, route)
        (Config.find_project config route.project_name))
  in
  match pdf_project with
  | Some (project, route) -> serve_cached_pdf oc ~meth ~config ~project route
  | None -> serve_static oc ~meth ~target path
;;

let handle_client ~config client_fd =
  Unix.setsockopt_float client_fd Unix.SO_RCVTIMEO socket_timeout_seconds;
  Unix.setsockopt_float client_fd Unix.SO_SNDTIMEO socket_timeout_seconds;
  let ic = Unix.in_channel_of_descr client_fd in
  let oc = Unix.out_channel_of_descr client_fd in
  (try
     match read_request ic with
     | Ok None -> ()
     | Ok (Some request) -> handle_request oc ~config request
     | Error status ->
       Logger.log_error ~context:"handle_client" (Error.server_bad_request status);
       respond_text oc ~meth:Get ~status status
   with
   | Sys_blocked_io | Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) ->
     Logger.debug "[handle_client] client timed out after %.0fs" socket_timeout_seconds
   | exn ->
     Logger.log_error
       ~context:"handle_client"
       (Error.server_socket_error (Printexc.to_string exn)));
  (* [ic] and [oc] share the descriptor: close it exactly once. *)
  Out_channel.close_noerr oc
;;

let parse_port = function
  | [ _ ] -> Ok default_port
  | [ _; arg ] ->
    (match int_of_string_opt arg with
     | Some port when port >= 1 && port <= 65535 -> Ok port
     | Some _ | None -> Error (Printf.sprintf "invalid port %S" arg))
  | _ -> Error "usage: serve [PORT]"
;;

let main () =
  Logger.init ();
  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  let port =
    match parse_port (Array.to_list Sys.argv) with
    | Ok port -> port
    | Error msg ->
      Logger.error "%s" msg;
      exit 2
  in
  if not (Fs.is_directory docroot)
  then (
    Logger.error "Directory '%s' does not exist. Run 'make build' first." docroot;
    exit 1);
  let config =
    match Config.load Config.config_file with
    | Ok config -> config
    | Error err ->
      Logger.log_error ~context:"Config.load" err;
      Logger.warn "On-demand PDF compilation is disabled.";
      Config.empty
  in
  let server_sock = Unix.socket ~cloexec:true Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt server_sock Unix.SO_REUSEADDR true;
  (match Unix.bind server_sock (Unix.ADDR_INET (Unix.inet_addr_any, port)) with
   | () -> ()
   | exception Unix.Unix_error (Unix.EADDRINUSE, _, _) ->
     Logger.log_error ~context:"server_init" (Error.server_port_in_use port);
     exit 1
   | exception exn ->
     Logger.log_error
       ~context:"server_init"
       (Error.server_socket_error (Printexc.to_string exn));
     exit 1);
  Unix.listen server_sock 128;
  Logger.info "BuzzYbis OCaml HTTP Server listening on http://localhost:%d" port;
  while true do
    match Unix.accept ~cloexec:true server_sock with
    | client_fd, (_ : Unix.sockaddr) ->
      ignore (Thread.create (fun () -> handle_client ~config client_fd) () : Thread.t)
    | exception Unix.Unix_error (Unix.EINTR, _, _) -> ()
    | exception exn ->
      Logger.log_error
        ~context:"accept_loop"
        (Error.server_socket_error (Printexc.to_string exn))
  done
;;
