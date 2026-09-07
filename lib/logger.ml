(* Production logging module using Jane Street's async_log *)

type t =
  | Info
  | Warn
  | Error
  | Debug

type level = t

let to_async_level = function
  | Info -> `Info
  | Warn -> `Info
  | Error -> `Error
  | Debug -> `Debug
;;

let init ?(level = Info) () =
  Async_log.Blocking.set_level (to_async_level level);
  Async_log.Blocking.set_output Async_log.Blocking.Output.stderr
;;

let info fmt = Async_log.Blocking.info fmt
let warn fmt = Async_log.Blocking.info fmt
let error fmt = Async_log.Blocking.error fmt
let debug fmt = Async_log.Blocking.debug fmt

let log_error ~context err =
  Async_log.Blocking.error "[%s] %s" context (Error.to_string err)
;;
