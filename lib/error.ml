(* Typed error domain shared by every module. *)

type fs_error =
  | Fs_read_failed of
      { path : string
      ; details : string
      }
  | Fs_write_failed of
      { path : string
      ; details : string
      }
  | Fs_mkdir_failed of
      { path : string
      ; details : string
      }
  | Fs_rmdir_failed of
      { path : string
      ; details : string
      }
  | Fs_remove_failed of
      { path : string
      ; details : string
      }
  | Fs_symlink_failed of
      { src : string
      ; dest : string
      ; details : string
      }
  | Fs_not_found of string
  | Fs_unsafe_name of string
  | Fs_traversal_rejected of
      { path : string
      ; reason : string
      }
  | Fs_symlink_escape of
      { root : string
      ; target : string
      }

type config_error =
  | Config_missing_file of string
  | Config_invalid_val of
      { field : string
      ; raw : string
      ; reason : string
      }

type json_error =
  | Json_parse_failed of
      { context : string
      ; raw : string
      ; details : string
      }

type network_error =
  | Net_http_failed of
      { url : string
      ; exit_code : int
      ; details : string
      }
  | Net_download_failed of
      { url : string
      ; dest : string
      ; details : string
      }
  | Net_github_failed of
      { endpoint : string
      ; details : string
      }

type process_error =
  | Process_spawn_failed of
      { prog : string
      ; details : string
      }
  | Process_failed of
      { prog : string
      ; exit_code : int
      ; output : string
      }

type typst_error =
  | Typst_missing_source of string
  | Typst_compile_failed of
      { src : string
      ; exit_code : int
      ; output : string
      }

type server_error =
  | Server_port_in_use of int
  | Server_socket_failed of string
  | Server_bad_request of string

type io_operation =
  | Read
  | Write
  | Mkdir
  | Rmdir
  | Remove
  | Stat
  | Symlink

type t =
  | Fs of fs_error
  | Config of config_error
  | Json of json_error
  | Network of network_error
  | Process of process_error
  | Typst of typst_error
  | Server of server_error

let truncate ?(max = 200) s =
  if String.length s <= max then s else String.sub s 0 max ^ "..."
;;

let to_string = function
  | Fs (Fs_read_failed { path; details }) ->
    Printf.sprintf "FS Read Error [%s]: %s" path details
  | Fs (Fs_write_failed { path; details }) ->
    Printf.sprintf "FS Write Error [%s]: %s" path details
  | Fs (Fs_mkdir_failed { path; details }) ->
    Printf.sprintf "FS Mkdir Error [%s]: %s" path details
  | Fs (Fs_rmdir_failed { path; details }) ->
    Printf.sprintf "FS Rmdir Error [%s]: %s" path details
  | Fs (Fs_remove_failed { path; details }) ->
    Printf.sprintf "FS Remove Error [%s]: %s" path details
  | Fs (Fs_symlink_failed { src; dest; details }) ->
    Printf.sprintf "FS Symlink Error [%s -> %s]: %s" src dest details
  | Fs (Fs_not_found path) -> Printf.sprintf "FS Not Found: %s" path
  | Fs (Fs_unsafe_name name) -> Printf.sprintf "Security Unsafe Name Rejected: %S" name
  | Fs (Fs_traversal_rejected { path; reason }) ->
    Printf.sprintf "Security Path Traversal Rejected [%s]: %s" path reason
  | Fs (Fs_symlink_escape { root; target }) ->
    Printf.sprintf "Security Symlink Escape [%s escapes %s]" target root
  | Config (Config_missing_file file) -> Printf.sprintf "Config Missing: %s" file
  | Config (Config_invalid_val { field; raw; reason }) ->
    Printf.sprintf "Config Invalid Value [%s = %s]: %s" field raw reason
  | Json (Json_parse_failed { context; raw; details }) ->
    Printf.sprintf "JSON Parse Error in %s: %s (raw: %s)" context details (truncate raw)
  | Network (Net_http_failed { url; exit_code; details }) ->
    Printf.sprintf "HTTP Error [%s] (curl exit %d): %s" url exit_code details
  | Network (Net_download_failed { url; dest; details }) ->
    Printf.sprintf "Download Error [%s -> %s]: %s" url dest details
  | Network (Net_github_failed { endpoint; details }) ->
    Printf.sprintf "GitHub API Error [%s]: %s" endpoint details
  | Process (Process_spawn_failed { prog; details }) ->
    Printf.sprintf "Process Spawn Error [%s]: %s" prog details
  | Process (Process_failed { prog; exit_code; output }) ->
    Printf.sprintf "Process Failed [%s] (exit %d):\n%s" prog exit_code output
  | Typst (Typst_missing_source src) -> Printf.sprintf "Typst Source Not Found: %s" src
  | Typst (Typst_compile_failed { src; exit_code; output }) ->
    Printf.sprintf "Typst Compile Error [%s] (exit %d):\n%s" src exit_code output
  | Server (Server_port_in_use port) ->
    Printf.sprintf "Server Port %d already in use" port
  | Server (Server_socket_failed msg) -> Printf.sprintf "Server Socket Error: %s" msg
  | Server (Server_bad_request req) -> Printf.sprintf "Server Bad Request: %s" req
;;

(* Constructors *)

let fs_write_failed ~path details = Fs (Fs_write_failed { path; details })
let not_found path = Fs (Fs_not_found path)
let unsafe_name name = Fs (Fs_unsafe_name name)
let traversal_rejected ~path ~reason = Fs (Fs_traversal_rejected { path; reason })
let symlink_escape ~root ~target = Fs (Fs_symlink_escape { root; target })
let config_missing file = Config (Config_missing_file file)

let config_invalid_val ~field ~raw reason =
  Config (Config_invalid_val { field; raw; reason })
;;

let json_parse_error ~context ~raw details =
  Json (Json_parse_failed { context; raw; details })
;;

let http_failed ~url ~exit_code details =
  Network (Net_http_failed { url; exit_code; details })
;;

let download_failed ~url ~dest details =
  Network (Net_download_failed { url; dest; details })
;;

let github_api_failed ~endpoint details =
  Network (Net_github_failed { endpoint; details })
;;

let process_spawn_failed ~prog details = Process (Process_spawn_failed { prog; details })

let process_failed ~prog ~exit_code output =
  Process (Process_failed { prog; exit_code; output })
;;

let typst_source_missing src = Typst (Typst_missing_source src)

let typst_compile_failed ~src ~exit_code output =
  Typst (Typst_compile_failed { src; exit_code; output })
;;

let server_port_in_use port = Server (Server_port_in_use port)
let server_socket_error msg = Server (Server_socket_failed msg)
let server_bad_request msg = Server (Server_bad_request msg)

let of_op ~op ~path details =
  match op with
  | Mkdir -> Fs (Fs_mkdir_failed { path; details })
  | Rmdir -> Fs (Fs_rmdir_failed { path; details })
  | Remove -> Fs (Fs_remove_failed { path; details })
  | Write -> Fs (Fs_write_failed { path; details })
  | Read | Stat | Symlink -> Fs (Fs_read_failed { path; details })
;;

let of_exn ~op ~path = function
  | Unix.Unix_error (Unix.ENOENT, _, _) -> Fs (Fs_not_found path)
  | Unix.Unix_error (err, fn, param) ->
    of_op ~op ~path (Printf.sprintf "%s(%s): %s" fn param (Unix.error_message err))
  | Sys_error msg -> of_op ~op ~path msg
  | exn -> of_op ~op ~path (Printexc.to_string exn)
;;
