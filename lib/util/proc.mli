(** Subprocess execution without a shell. Arguments are passed as an argv vector, so
    untrusted values (URLs, file names, repository names) can never be interpreted by a
    shell. *)

type output =
  { status : Unix.process_status
  ; stdout : string
  ; stderr : string
  }

(** [exit_code status] folds a process status into a conventional shell exit code
    ([128 + signal] for signals). *)
val exit_code : Unix.process_status -> int

(** [succeeded status] is [true] iff the process exited with code 0. *)
val succeeded : Unix.process_status -> bool

(** [run prog args] runs [prog] (looked up in [PATH]) with [args], stdin connected to
    [/dev/null], and captures stdout and stderr separately. Only spawn failures are
    errors; a non-zero exit is reported through [output.status]. *)
val run : string -> string list -> (output, Error.t) result

(** [run_checked prog args] is [run] but a non-zero exit status is also an error. *)
val run_checked : string -> string list -> (output, Error.t) result
