(** Static file server, on-demand cached PDF compilation, and HTTP request handling. Path
    validation, resolution, and compilation return typed [('a, Error.t) result] values. *)

(** [mime_type path] returns the MIME Content-Type header string based on the extension of
    [path]. *)
val mime_type : string -> string

(** [parse_cached_pdf_uri uri] inspects [uri] to see if it targets an on-demand PDF route,
    returning [Some (project_name, slug, pdf_filename)] if matched. *)
val parse_cached_pdf_uri : string -> (string * string * string) option

(** [record_pdf_download ~cached_dir ~pdf_filename ~full_path] updates access timestamps
    for cached PDF [pdf_filename] in [.downloads.json]. *)
val record_pdf_download
  :  cached_dir:string
  -> pdf_filename:string
  -> full_path:string
  -> (unit, Error.t) result

(** [compile_cached_pdf ~project_name ~slug ~cached_dir ~full_cached_path] compiles a
    Typst article into a standalone PDF, caching the result at [full_cached_path]. *)
val compile_cached_pdf
  :  project_name:string
  -> slug:string
  -> cached_dir:string
  -> full_cached_path:string
  -> (string, Error.t) result

(** [is_regular_file path] checks if [path] targets an existing regular file. *)
val is_regular_file : string -> bool

(** [sanitize_path uri_path] normalizes [uri_path], returning an error if directory
    traversal is detected. *)
val sanitize_path : string -> (string, Error.t) result

(** [is_within_root ~root ~target] verifies using realpath that [target] does not escape
    [root]. *)
val is_within_root : root:string -> target:string -> (unit, Error.t) result

(** [resolve_file ~docroot ~uri_path] maps an incoming HTTP URI path to a verified safe
    filesystem path. *)
val resolve_file : docroot:string -> uri_path:string -> (string, Error.t) result

(** [default_security_headers] contains standard HTTP security headers (nosniff,
    SAMEORIGIN, referrer-policy). *)
val default_security_headers : (string * string) list

(** [format_headers headers] formats a list of [(name, value)] pairs into HTTP header
    lines. *)
val format_headers : (string * string) list -> string

(** [send_response oc ~status ~content_type ?headers body] sends a complete HTTP response. *)
val send_response
  :  out_channel
  -> status:string
  -> content_type:string
  -> ?headers:(string * string) list
  -> string
  -> unit

(** [send_file_headers oc ~status ~content_type ~content_length ?headers ()] transmits
    HTTP response headers prior to file streaming. *)
val send_file_headers
  :  out_channel
  -> status:string
  -> content_type:string
  -> content_length:int
  -> ?headers:(string * string) list
  -> unit
  -> unit

(** [send_file_body oc path] streams the binary contents of file [path] to [oc] using a
    64KB buffer. *)
val send_file_body : out_channel -> string -> unit

(** [handle_client ~docroot ~client_fd] processes an individual client HTTP connection. *)
val handle_client : docroot:string -> client_fd:Unix.file_descr -> unit

(** [main ()] CLI entry point for the HTTP server listening on configured port. *)
val main : unit -> unit
