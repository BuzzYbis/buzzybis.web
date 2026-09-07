(** Remote repository synchronization, Typst compilation, cache eviction, and fetch CLI.
    State operations and compilation return typed [('a, Error.t) result] values. *)

(** [parse_github_repo ~repo_url ~default_owner ~fallback_repo] parses a GitHub URL or
    short identifier into an [(owner, repo)] tuple. *)
val parse_github_repo
  :  repo_url:string
  -> default_owner:string
  -> fallback_repo:string
  -> string * string

(** [cleanup_unconfigured_projects config] cleans up project directories from disk that
    are no longer configured in [projects.toml]. *)
val cleanup_unconfigured_projects : Config.t -> unit

(** [get_remote_blog_sha ~owner ~repo] queries the GitHub API for the latest commit SHA
    modifying the [blog/] directory. *)
val get_remote_blog_sha : owner:string -> repo:string -> (string option, Error.t) result

(** [clean_expired_cached_pdfs config project] evicts on-demand compiled PDFs that have
    not been downloaded within the expiration TTL. *)
val clean_expired_cached_pdfs : Config.t -> Config.project -> unit

(** [ensure_clean_repo_site config] creates or updates the [site/project] symlink pointing
    to the external project build directory. *)
val ensure_clean_repo_site : Config.t -> (unit, Error.t) result

(** [download_repo_blog_files ~temp_blog files] downloads companion assets and source
    files for a project into [temp_blog]. *)
val download_repo_blog_files
  :  temp_blog:string
  -> (string * string) list
  -> (unit, Error.t) result

(** [compile_typ_posts ~temp_blog ~temp_root ~html_dir ~project font_arg typ_files]
    compiles all Typst [.typ] blogposts in [typ_files] into HTML pages. *)
val compile_typ_posts
  :  temp_blog:string
  -> temp_root:string
  -> html_dir:string
  -> project:Config.project
  -> string
  -> (string * string) list
  -> (string list, Error.t) result

(** [copy_companion_assets ~temp_blog ~html_dir files] copies non-Typst assets (images,
    diagrams, scripts) into the project HTML output directory. *)
val copy_companion_assets
  :  temp_blog:string
  -> html_dir:string
  -> (string * string) list
  -> unit

(** [clean_stale_html_and_legacy ~html_dir ~project_dir keep_html] removes HTML files no
    longer present in [keep_html] and removes stray files from [project_dir]. *)
val clean_stale_html_and_legacy
  :  html_dir:string
  -> project_dir:string
  -> string list
  -> unit

(** [invalidate_cached_pdfs cached_pdf_dir] removes all cached compiled PDFs when the
    upstream repository SHA has changed. *)
val invalidate_cached_pdfs : string -> unit

(** [fetch_and_compile_repo_blogposts config state_ref force_rebuild project] checks for
    changes, downloads new posts, and compiles them for [project]. *)
val fetch_and_compile_repo_blogposts
  :  Config.t
  -> (string * string) list ref
  -> bool
  -> Config.project
  -> (bool, Error.t) result

(** [run_sync config state_ref ~force_rebuild] iterates over all configured projects,
    fetching updates and triggering a Soupault site rebuild if needed. *)
val run_sync : Config.t -> (string * string) list ref -> force_rebuild:bool -> unit

(** [main ()] CLI entry point for the fetch tool supporting [--watch], [--force], and
    [--pages-only]. *)
val main : unit -> unit
