(** Custom typed error domain for BuzzYbis website. All failure conditions across
    filesystem, configuration, JSON, network, Typst compilation, HTML parsing, and HTTP
    serving are represented as values. *)

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

(** The primary error type for all BuzzYbis operations. *)
type t =
  | Fs of fs_error
  | Config of config_error
  | Json of json_error
  | Network of network_error
  | Typst of typst_error
  | Server of server_error
  | Html of html_error

(** [to_string t] converts error [t] into a formatted human-readable diagnostic string. *)
val to_string : t -> string

(** [pp fmt t] prints error [t] into formatter [fmt]. *)
val pp : Format.formatter -> t -> unit

(** Helper constructors *)

(** [fs_read_failed ~path details] creates an [Fs_read_failed] error. *)
val fs_read_failed : path:string -> string -> t

(** [fs_write_failed ~path details] creates an [Fs_write_failed] error. *)
val fs_write_failed : path:string -> string -> t

(** [fs_mkdir_failed ~path details] creates an [Fs_mkdir_failed] error. *)
val fs_mkdir_failed : path:string -> string -> t

(** [fs_rm_failed ~path details] creates an [Fs_remove_failed] error. *)
val fs_rm_failed : path:string -> string -> t

(** [fs_symlink_failed ~src ~dest details] creates an [Fs_symlink_failed] error. *)
val fs_symlink_failed : src:string -> dest:string -> string -> t

(** [not_found path] creates an [Fs_not_found] error. *)
val not_found : string -> t

(** [traversal_rejected ~path ~reason] creates an [Fs_traversal_rejected] error. *)
val traversal_rejected : path:string -> reason:string -> t

(** [symlink_escape ~root ~target] creates an [Fs_symlink_escape] error. *)
val symlink_escape : root:string -> target:string -> t

(** [config_missing path] creates a [Config_missing_file] error. *)
val config_missing : string -> t

(** [config_parse_error ~file ?line msg] creates a [Config_invalid_val] error. *)
val config_parse_error : file:string -> ?line:int -> string -> t

(** [config_invalid_val ~field ~raw reason] creates a [Config_invalid_val] error. *)
val config_invalid_val : field:string -> raw:string -> string -> t

(** [json_parse_error ~context ~raw details] creates a [Json_parse_failed] error. *)
val json_parse_error : context:string -> raw:string -> string -> t

(** [json_write_error ~path details] creates a [Json_write_failed] error. *)
val json_write_error : path:string -> string -> t

(** [http_failed ~url ?status_code details] creates a [Net_http_failed] error. *)
val http_failed : url:string -> ?status_code:int -> string -> t

(** [download_failed ~url ~dest details] creates a [Net_download_failed] error. *)
val download_failed : url:string -> dest:string -> string -> t

(** [github_api_failed ~endpoint details] creates a [Net_github_failed] error. *)
val github_api_failed : endpoint:string -> string -> t

(** [typst_source_missing src] creates a [Typst_missing_source] error. *)
val typst_source_missing : string -> t

(** [typst_compile_failed ~src ~exit_code ~output] creates a [Typst_compile_failed] error. *)
val typst_compile_failed : src:string -> exit_code:int -> output:string -> t

(** [server_port_in_use ~port details] creates a [Server_port_in_use] error. *)
val server_port_in_use : port:int -> string -> t

(** [server_socket_error msg] creates a [Server_socket_failed] error. *)
val server_socket_error : string -> t

(** [server_malformed_request msg] creates a [Server_bad_request] error. *)
val server_malformed_request : string -> t

(** [server_resource_not_found uri] creates a [Server_not_found] error. *)
val server_resource_not_found : string -> t

(** [html_parse_failed ~context details] creates an [Html_parse_failed] error. *)
val html_parse_failed : context:string -> string -> t

(** [of_unix_error ~op ~path err fn param] maps a system Unix exception to a typed [t]. *)
val of_unix_error : op:io_operation -> path:string -> Unix.error -> string -> string -> t

(** [of_sys_error ~op ~path msg] maps a system Sys exception to a typed [t]. *)
val of_sys_error : op:io_operation -> path:string -> string -> t

(** [of_exn ~op ~path exn] maps any caught system exception to a typed [t]. *)
val of_exn : op:io_operation -> path:string -> exn -> t
