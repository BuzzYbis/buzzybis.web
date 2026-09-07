(* Subprocess execution without a shell: arguments are passed as an argv vector, so no
   quoting or escaping of untrusted values is ever needed. *)

type output =
  { status : Unix.process_status
  ; stdout : string
  ; stderr : string
  }

let exit_code = function
  | Unix.WEXITED code -> code
  | Unix.WSIGNALED signal -> 128 + signal
  | Unix.WSTOPPED _ -> 1
;;

let succeeded = function
  | Unix.WEXITED 0 -> true
  | Unix.WEXITED _ | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> false
;;

let close_noerr fd =
  try Unix.close fd with
  | Unix.Unix_error _ -> ()
;;

let rec waitpid pid =
  try snd (Unix.waitpid [] pid) with
  | Unix.Unix_error (Unix.EINTR, _, _) -> waitpid pid
;;

(* Spawn [prog] with stdin on /dev/null, stdout on a pipe and stderr on [err_file].
   Returns the child pid and the read end of the stdout pipe. *)
let spawn prog argv ~err_file =
  let devnull = Unix.openfile "/dev/null" [ Unix.O_RDONLY; Unix.O_CLOEXEC ] 0 in
  let err_fd =
    try Unix.openfile err_file [ Unix.O_WRONLY; Unix.O_TRUNC; Unix.O_CLOEXEC ] 0o600 with
    | exn ->
      close_noerr devnull;
      raise exn
  in
  let out_r, out_w =
    try Unix.pipe ~cloexec:true () with
    | exn ->
      close_noerr devnull;
      close_noerr err_fd;
      raise exn
  in
  let release () =
    close_noerr devnull;
    close_noerr err_fd;
    close_noerr out_w
  in
  match Unix.create_process prog argv devnull out_w err_fd with
  | pid ->
    release ();
    pid, out_r
  | exception exn ->
    release ();
    close_noerr out_r;
    raise exn
;;

let run prog args =
  let argv = Array.of_list (prog :: args) in
  let run_with_err_file err_file =
    let pid, out_r = spawn prog argv ~err_file in
    let ic = Unix.in_channel_of_descr out_r in
    let stdout =
      Fun.protect
        ~finally:(fun () -> In_channel.close_noerr ic)
        (fun () -> In_channel.input_all ic)
    in
    let status = waitpid pid in
    let stderr = In_channel.with_open_bin err_file In_channel.input_all in
    { status; stdout; stderr }
  in
  match
    let err_file = Filename.temp_file "buzzybis-" ".stderr" in
    Fun.protect
      ~finally:(fun () ->
        try Sys.remove err_file with
        | Sys_error _ -> ())
      (fun () -> run_with_err_file err_file)
  with
  | output -> Ok output
  | exception Unix.Unix_error (err, fn, arg) ->
    Error
      (Error.process_spawn_failed
         ~prog
         (Printf.sprintf "%s(%s): %s" fn arg (Unix.error_message err)))
  | exception Sys_error msg -> Error (Error.process_spawn_failed ~prog msg)
;;

let run_checked prog args =
  match run prog args with
  | Error _ as err -> err
  | Ok output when succeeded output.status -> Ok output
  | Ok output ->
    Error
      (Error.process_failed
         ~prog
         ~exit_code:(exit_code output.status)
         (String.trim (output.stdout ^ "\n" ^ output.stderr)))
;;
