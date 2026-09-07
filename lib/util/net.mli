(** HTTP helpers on top of curl. Only [https] URLs are allowed, redirects included. *)

(** [http_get url] fetches [url] and returns the response body. HTTP error statuses are
    not failures here: callers inspect the body (GitHub returns JSON error objects). *)
val http_get : string -> (string, Error.t) result

(** [download_file ~url ~dest] downloads [url] into [dest] atomically. Any HTTP error
    status is a failure and leaves no partial file behind. *)
val download_file : url:string -> dest:string -> (unit, Error.t) result
