(** GitHub synchronization, Typst compilation, cache eviction and the fetch CLI. *)

(** [parse_github_repo ~repo_url ~default_owner ~fallback_repo] extracts [(owner, repo)]
    from a GitHub URL, falling back to the defaults for anything else. *)
val parse_github_repo
  :  repo_url:string
  -> default_owner:string
  -> fallback_repo:string
  -> string * string

(** [main ()] entry point of the fetch tool: [--force], [--watch], [--pages-only],
    [--poll SECONDS]. *)
val main : unit -> unit
