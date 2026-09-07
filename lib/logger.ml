(* Logging backed by Async_log's blocking interface, writing to stderr. *)

type level =
  | Info
  | Warn
  | Error
  | Debug

let to_async_level = function
  | Info | Warn -> `Info
  | Error -> `Error
  | Debug -> `Debug
;;

let init ?(level = Info) () =
  Async_log.Blocking.set_level (to_async_level level);
  Async_log.Blocking.set_output Async_log.Blocking.Output.stderr
;;

let info fmt = Async_log.Blocking.info fmt
let warn fmt = Async_log.Blocking.info ("[WARN] " ^^ fmt)
let error fmt = Async_log.Blocking.error fmt
let debug fmt = Async_log.Blocking.debug fmt

let log_error ~context err =
  Async_log.Blocking.error "[%s] %s" context (Error.to_string err)
;;

let report ~context = function
  | Ok () -> ()
  | Error err -> log_error ~context err
;;
