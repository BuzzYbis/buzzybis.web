(** Configuration types and TOML parser for [projects.toml]. Parsing and file state
    operations return typed [('a, Error.t) result] values. *)

type download_item =
  { label : string
  ; url : string
  }

type project =
  { name : string
  ; mutable title : string
  ; mutable description : string
  ; mutable collaborators : string list
  ; mutable repo_url : string
  ; mutable tags : string list
  ; mutable downloads : download_item list
  }

(** The application configuration type. *)
type t =
  { mutable projects_dir : string
  ; mutable poll_interval : int
  ; mutable projects : project list
  }

type app_config = t

(** [github_user] is the default GitHub organization/user to track. *)
val github_user : string

(** [config_file] is the default filename of the configuration file. *)
val config_file : string

(** [parse_string_list str] parses a TOML inline array of strings, e.g.
    ["[\"a\", \"b\"]"]. *)
val parse_string_list : string -> string list

(** [parse_string_val raw] strips surrounding quotes and whitespace from [raw]. *)
val parse_string_val : string -> string

(** [expand_path path] expands leading [~/] or relative paths to absolute filesystem
    paths. *)
val expand_path : string -> string

(** [get_projects_dir t] returns the resolved output directory for projects. *)
val get_projects_dir : t -> string

(** [get_projects_dir_standalone ()] reads the project directory path from the
    configuration file without loading all project metadata. *)
val get_projects_dir_standalone : unit -> string

(** [load_projects_toml path] loads and parses the TOML configuration file at [path]. *)
val load_projects_toml : string -> (t, Error.t) result

(** [get_state_file t] returns the path to the fetch state JSON file for [t]. *)
val get_state_file : t -> string

(** [load_fetch_state t] reads the map of project names to commit SHAs. *)
val load_fetch_state : t -> (string * string) list

(** [save_fetch_state t state] persists the project commit SHAs atomically to disk. *)
val save_fetch_state : t -> (string * string) list -> (unit, Error.t) result
