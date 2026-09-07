(** Filesystem utilities: safe names, atomic writes, recursive operations. Every
    operation returns a typed [('a, Error.t) result] instead of raising. *)

(** [is_safe_name s] is [true] iff [s] is a single non-hidden path component made only of
    ASCII letters, digits, ['-'], ['_'] and ['.']. Such a name can never escape its
    directory or carry shell/HTTP metacharacters. *)
val is_safe_name : string -> bool

(** [check_safe_name s] is [Ok s] when {!is_safe_name} holds, [Error] otherwise. *)
val check_safe_name : string -> (string, Error.t) result

(** [remove_noerr path] removes [path] if possible, ignoring failures. *)
val remove_noerr : string -> unit

(** [is_regular_file path] follows symlinks and checks for a regular file. *)
val is_regular_file : string -> bool

(** [is_directory path] is [true] iff [path] exists and is a directory. *)
val is_directory : string -> bool

(** [atomic_write_file ~path ~content] writes [content] to a temporary file and renames it
    onto [path], so readers never observe a partially written file. *)
val atomic_write_file : path:string -> content:string -> (unit, Error.t) result

(** [write_json ~path json] serializes [json] and writes it atomically. *)
val write_json : path:string -> Yojson.Safe.t -> (unit, Error.t) result

(** [read_json_assoc path] reads a JSON object from [path]. A missing, unreadable or
    non-object file yields [[]]. *)
val read_json_assoc : string -> (string * Yojson.Safe.t) list

(** [mkdir_p dir] creates [dir] and its parents. *)
val mkdir_p : string -> (unit, Error.t) result

(** [mkdir_all dirs] is {!mkdir_p} applied to every directory in order. *)
val mkdir_all : string list -> (unit, Error.t) result

(** [rm_rf path] removes [path] recursively. Symbolic links are removed, never
    followed. A missing [path] is not an error. *)
val rm_rf : string -> (unit, Error.t) result

(** [symlink_force ~src ~dest] replaces any file or link at [dest] with a symlink to
    [src]. *)
val symlink_force : src:string -> dest:string -> (unit, Error.t) result

(** [cp_r ~src ~dest] copies a file or directory tree. *)
val cp_r : src:string -> dest:string -> (unit, Error.t) result

(** [list_dir path] lists the entries of directory [path], or [[]] if it is not a
    readable directory. *)
val list_dir : string -> string list

(** [is_basename s] is [true] iff [s] is a single path component: non-empty, not ["."] or
    [".."], and free of directory separators and NUL bytes. Looser than
    {!is_safe_name}; suitable for file names listed by a trusted API. *)
val is_basename : string -> bool

(** [check_basename s] is [Ok s] when {!is_basename} holds, [Error] otherwise. *)
val check_basename : string -> (string, Error.t) result

(** [kind path] is the type of the entry at [path] without following symlinks, or [None]
    if it does not exist. *)
val kind : string -> Unix.file_kind option
