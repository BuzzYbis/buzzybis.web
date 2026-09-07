(** URL parsing and path validation utilities. *)

(** [is_abs_or_remote uri] checks if [uri] is an absolute path or external URL. *)
val is_abs_or_remote : string -> bool

(** [default_title_of_basename basename] formats a title from a file basename. *)
val default_title_of_basename : string -> string
