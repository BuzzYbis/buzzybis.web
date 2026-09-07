(** Static file server for the [build/] directory with on-demand compilation of cached
    article PDFs.

    Request targets are normalized and resolved with [realpath] so they can never leave
    the document root. Cached PDF routes only accept configured project names and
    slugs made of safe characters. Request lines and headers are bounded in size and
    sockets carry read/write timeouts. *)

(** [mime_type path] is the [Content-Type] for [path], by extension. *)
val mime_type : string -> string

(** A request for an on-demand article PDF. *)
type pdf_route =
  { project_name : string
  ; slug : string
  ; pdf_filename : string
  }

(** [parse_pdf_route path] recognizes [/project/<name>/cached_pdf/<slug>.pdf] and
    [/project/<name>/html/cached_pdf/<slug>.pdf] when [<name>] and [<slug>] are safe
    names (see {!Util.Fs.is_safe_name}). *)
val parse_pdf_route : string -> pdf_route option

(** [normalize_path path] collapses empty, ["."] and [".."] segments of a decoded URL
    path into a relative filesystem path, failing if [".."] would climb above the
    root. *)
val normalize_path : string -> (string, Error.t) result

(** [main ()] serves [build/] on the port given as first argument (default 8000). *)
val main : unit -> unit
