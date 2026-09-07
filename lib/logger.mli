(** Production logging module using Jane Street's async_log. *)

type t =
  | Info
  | Warn
  | Error
  | Debug

type level = t

(** [init ?level ()] initializes the Async_log backend with log level [level] emitting to
    stderr. *)
val init : ?level:t -> unit -> unit

(** [info fmt] logs an informational message with millisecond precision timestamp. *)
val info : ('a, unit, string, unit) format4 -> 'a

(** [warn fmt] logs a warning message. *)
val warn : ('a, unit, string, unit) format4 -> 'a

(** [error fmt] logs an error message. *)
val error : ('a, unit, string, unit) format4 -> 'a

(** [debug fmt] logs a debug message. *)
val debug : ('a, unit, string, unit) format4 -> 'a

(** [log_error ~context err] logs a typed [Error.t] labeled with [context]. *)
val log_error : context:string -> Error.t -> unit
