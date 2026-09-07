(** Typed error domain shared by every module. All failure conditions across the
    filesystem, configuration, JSON, network, subprocesses, Typst compilation and HTTP
    serving are represented as values of type {!t}. *)

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

(** The filesystem operation that was being attempted when an exception was raised. *)
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

(** [to_string t] renders [t] as a single human-readable diagnostic line. *)
val to_string : t -> string

(** {1 Constructors} *)

val fs_write_failed : path:string -> string -> t
val not_found : string -> t
val unsafe_name : string -> t
val traversal_rejected : path:string -> reason:string -> t
val symlink_escape : root:string -> target:string -> t
val config_missing : string -> t
val config_invalid_val : field:string -> raw:string -> string -> t
val json_parse_error : context:string -> raw:string -> string -> t
val http_failed : url:string -> exit_code:int -> string -> t
val download_failed : url:string -> dest:string -> string -> t
val github_api_failed : endpoint:string -> string -> t
val process_spawn_failed : prog:string -> string -> t
val process_failed : prog:string -> exit_code:int -> string -> t
val typst_source_missing : string -> t
val typst_compile_failed : src:string -> exit_code:int -> string -> t
val server_port_in_use : int -> t
val server_socket_error : string -> t
val server_bad_request : string -> t

(** [of_exn ~op ~path exn] maps a [Unix.Unix_error] or [Sys_error] raised while performing
    [op] on [path] to a typed error. [ENOENT] always becomes [Fs_not_found]. *)
val of_exn : op:io_operation -> path:string -> exn -> t
