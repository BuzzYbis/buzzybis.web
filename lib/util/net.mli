(** Network and external process utilities. *)

(** [run_cmd cmd] executes [cmd] synchronously in a subshell. *)
val run_cmd : string -> (Unix.process_status * string, Error.t) result

(** [http_get url] performs an HTTP GET request using curl. *)
val http_get : string -> (string, Error.t) result

(** [download_file ~url ~dest] streams the file from [url] to [dest]. *)
val download_file : url:string -> dest:string -> (unit, Error.t) result
