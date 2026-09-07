(** Logging backed by Async_log's blocking interface, writing to stderr. *)

type level =
  | Info
  | Warn
  | Error
  | Debug

(** [init ?level ()] configures the backend to emit messages of at least [level] to
    stderr. *)
val init : ?level:level -> unit -> unit

val info : ('a, unit, string, unit) format4 -> 'a
val warn : ('a, unit, string, unit) format4 -> 'a
val error : ('a, unit, string, unit) format4 -> 'a
val debug : ('a, unit, string, unit) format4 -> 'a

(** [log_error ~context err] logs a typed error prefixed with [context]. *)
val log_error : context:string -> Error.t -> unit

(** [report ~context result] logs the error of [result], if any. Use it at the points
    where a failure is deliberately non-fatal. *)
val report : context:string -> (unit, Error.t) result -> unit
