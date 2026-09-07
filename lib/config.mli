(** Configuration types and a minimal TOML reader for [projects.toml]. *)

type download_item =
  { label : string
  ; url : string
  }

type project =
  { name : string (** Section name; also the directory and URL segment. *)
  ; title : string
  ; description : string
  ; collaborators : string list
  ; repo_url : string
  ; tags : string list
  ; downloads : download_item list
  }

type t =
  { projects_dir : string
  ; poll_interval : int
  ; projects : project list
  }

(** On-disk layout of one project under {!projects_dir}. *)
type project_paths =
  { project_dir : string
  ; html_dir : string
  ; pdfs_dir : string
  ; cached_pdf_dir : string
  }

(** Default GitHub owner used when a project omits [repo]. *)
val github_user : string

(** Default configuration file name. *)
val config_file : string

(** Default value of [projects_dir]. *)
val default_projects_dir : string

(** Scratch directory where fetched Typst sources are staged, relative to the repository
    root. *)
val fetch_tmp_dir : string

(** A configuration with no projects and default settings. *)
val empty : t

(** [load path] reads and parses the configuration file at [path]. Project section names
    must satisfy {!Util.Fs.is_safe_name}. *)
val load : string -> (t, Error.t) result

(** [projects_dir t] is the absolute, [~]-expanded output directory for projects. *)
val projects_dir : t -> string

(** [project_paths t project] is the on-disk layout of [project]. *)
val project_paths : t -> project -> project_paths

(** [project_url_path project] is the site path of [project], without trailing slash. *)
val project_url_path : project -> string

(** [find_project t name] looks a project up by its section name. *)
val find_project : t -> string -> project option

(** [load_fetch_state t] reads the map of project names to last synced commit SHAs. *)
val load_fetch_state : t -> (string * string) list

(** [save_fetch_state t state] persists the commit SHA map atomically. *)
val save_fetch_state : t -> (string * string) list -> (unit, Error.t) result
