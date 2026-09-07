(** Filesystem utilities with scoped channel resource management and atomic writes. *)

(** [with_in_channel ~path f] safely opens [path] for text reading. *)
val with_in_channel
  :  path:string
  -> (in_channel -> ('a, Error.t) result)
  -> ('a, Error.t) result

(** [with_out_channel ~path f] safely opens [path] for text writing. *)
val with_out_channel
  :  path:string
  -> (out_channel -> ('a, Error.t) result)
  -> ('a, Error.t) result

(** [atomic_write_file ~path ~content] atomically writes [content] into [path]. *)
val atomic_write_file : path:string -> content:string -> (unit, Error.t) result

(** [mkdir_p dir] recursively creates directory [dir]. *)
val mkdir_p : string -> (unit, Error.t) result

(** [rm_rf path] recursively deletes [path]. *)
val rm_rf : string -> (unit, Error.t) result

(** [symlink_force ~src ~dest] atomically creates a symlink at [dest] pointing to [src]. *)
val symlink_force : src:string -> dest:string -> (unit, Error.t) result

(** [cp_r ~src ~dest] recursively copies files and directories from [src] to [dest]. *)
val cp_r : src:string -> dest:string -> (unit, Error.t) result
