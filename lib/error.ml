(* Custom typed error domain for BuzzYbis website *)

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
  | Config_missing_field of
      { section : string
      ; field : string
      }
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
  | Json_write_failed of
      { path : string
      ; details : string
      }

type network_error =
  | Net_http_failed of
      { url : string
      ; status_code : int option
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

type typst_error =
  | Typst_missing_source of string
  | Typst_compile_failed of
      { src : string
      ; exit_code : int
      ; output : string
      }

type server_error =
  | Server_port_in_use of
      { port : int
      ; details : string
      }
  | Server_socket_failed of string
  | Server_bad_request of string
  | Server_not_found of string

type html_error =
  | Html_parse_failed of
      { context : string
      ; details : string
      }

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
  | Typst of typst_error
  | Server of server_error
  | Html of html_error

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
  | Fs (Fs_traversal_rejected { path; reason }) ->
    Printf.sprintf "Security Path Traversal Rejected [%s]: %s" path reason
  | Fs (Fs_symlink_escape { root; target }) ->
    Printf.sprintf "Security Symlink Escape [%s escapes %s]" target root
  | Config (Config_missing_file file) -> Printf.sprintf "Config Missing: %s" file
  | Config (Config_missing_field { section; field }) ->
    Printf.sprintf "Config Missing Field [%s.%s]" section field
  | Config (Config_invalid_val { field; raw; reason }) ->
    Printf.sprintf "Config Invalid Value [%s = %s]: %s" field raw reason
  | Json (Json_parse_failed { context; raw; details }) ->
    Printf.sprintf "JSON Parse Error in %s: %s (raw: %s)" context details raw
  | Json (Json_write_failed { path; details }) ->
    Printf.sprintf "JSON Write Error [%s]: %s" path details
  | Network (Net_http_failed { url; status_code; details }) ->
    let code_str =
      match status_code with
      | Some c -> Printf.sprintf " (status %d)" c
      | None -> ""
    in
    Printf.sprintf "HTTP Error [%s%s]: %s" url code_str details
  | Network (Net_download_failed { url; dest; details }) ->
    Printf.sprintf "Download Error [%s -> %s]: %s" url dest details
  | Network (Net_github_failed { endpoint; details }) ->
    Printf.sprintf "GitHub API Error [%s]: %s" endpoint details
  | Typst (Typst_missing_source src) -> Printf.sprintf "Typst Source Not Found: %s" src
  | Typst (Typst_compile_failed { src; exit_code; output }) ->
    Printf.sprintf "Typst Compile Error [%s] (exit %d):\n%s" src exit_code output
  | Server (Server_port_in_use { port; details }) ->
    Printf.sprintf "Server Port %d in use: %s" port details
  | Server (Server_socket_failed msg) -> Printf.sprintf "Server Socket Error: %s" msg
  | Server (Server_bad_request req) -> Printf.sprintf "Server Bad Request: %s" req
  | Server (Server_not_found uri) -> Printf.sprintf "Server 404 Not Found: %s" uri
  | Html (Html_parse_failed { context; details }) ->
    Printf.sprintf "HTML Parse Error in %s: %s" context details
;;

let pp fmt err = Format.fprintf fmt "%s" (to_string err)

(* Helper constructors *)
let fs_read_failed ~path details = Fs (Fs_read_failed { path; details })
let fs_write_failed ~path details = Fs (Fs_write_failed { path; details })
let fs_mkdir_failed ~path details = Fs (Fs_mkdir_failed { path; details })
let fs_rm_failed ~path details = Fs (Fs_remove_failed { path; details })
let fs_symlink_failed ~src ~dest details = Fs (Fs_symlink_failed { src; dest; details })
let not_found path = Fs (Fs_not_found path)
let traversal_rejected ~path ~reason = Fs (Fs_traversal_rejected { path; reason })
let symlink_escape ~root ~target = Fs (Fs_symlink_escape { root; target })
let config_missing file = Config (Config_missing_file file)

let config_parse_error ~file ?line message =
  let reason =
    match line with
    | Some l -> Printf.sprintf "line %d: %s" l message
    | None -> message
  in
  Config (Config_invalid_val { field = file; raw = ""; reason })
;;

let config_invalid_val ~field ~raw reason =
  Config (Config_invalid_val { field; raw; reason })
;;

let json_parse_error ~context ~raw details =
  Json (Json_parse_failed { context; raw; details })
;;

let json_write_error ~path details = Json (Json_write_failed { path; details })

let http_failed ~url ?status_code details =
  Network (Net_http_failed { url; status_code; details })
;;

let download_failed ~url ~dest details =
  Network (Net_download_failed { url; dest; details })
;;

let github_api_failed ~endpoint details =
  Network (Net_github_failed { endpoint; details })
;;

let typst_source_missing src = Typst (Typst_missing_source src)

let typst_compile_failed ~src ~exit_code ~output =
  Typst (Typst_compile_failed { src; exit_code; output })
;;

let server_port_in_use ~port details = Server (Server_port_in_use { port; details })
let server_socket_error msg = Server (Server_socket_failed msg)
let server_malformed_request msg = Server (Server_bad_request msg)
let server_resource_not_found uri = Server (Server_not_found uri)
let html_parse_failed ~context details = Html (Html_parse_failed { context; details })

let of_unix_error ~op ~path err fn param =
  let details = Printf.sprintf "%s(%s): %s" fn param (Unix.error_message err) in
  match err with
  | Unix.ENOENT -> Fs (Fs_not_found path)
  | Unix.EACCES -> Fs (Fs_read_failed { path; details = "Permission denied: " ^ details })
  | _ ->
    (match op with
     | Mkdir -> Fs (Fs_mkdir_failed { path; details })
     | Rmdir -> Fs (Fs_rmdir_failed { path; details })
     | Remove -> Fs (Fs_remove_failed { path; details })
     | Write -> Fs (Fs_write_failed { path; details })
     | Read | Stat | Symlink -> Fs (Fs_read_failed { path; details }))
;;

let of_sys_error ~op ~path msg =
  match op with
  | Mkdir -> Fs (Fs_mkdir_failed { path; details = msg })
  | Rmdir -> Fs (Fs_rmdir_failed { path; details = msg })
  | Remove -> Fs (Fs_remove_failed { path; details = msg })
  | Write -> Fs (Fs_write_failed { path; details = msg })
  | Read | Stat | Symlink -> Fs (Fs_read_failed { path; details = msg })
;;

let of_exn ~op ~path = function
  | Unix.Unix_error (err, fn, param) -> of_unix_error ~op ~path err fn param
  | Sys_error msg -> of_sys_error ~op ~path msg
  | exn -> Fs (Fs_read_failed { path; details = Printexc.to_string exn })
;;
