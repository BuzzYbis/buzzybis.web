(** HTML page generation for project overviews, articles, directory, and home page.
    Generators return typed [('a, Error.t) result] values. *)

(** [format_blogpost_html ~project_name ~slug ?repo_url ?default_tags raw_html] transforms
    raw Typst HTML output into a fully styled blogpost article page with metadata,
    headers, and responsive styling. *)
val format_blogpost_html
  :  project_name:string
  -> slug:string
  -> ?repo_url:string
  -> ?default_tags:string list
  -> string
  -> (string, Error.t) result

(** [discover_project_downloads config project] scans the project directory for static
    PDFs and attaches them to [project.downloads]. *)
val discover_project_downloads : Config.t -> Config.project -> unit

(** [generate_project_page config project] generates the project landing page [index.html]
    displaying metadata, tags, download links, and dynamic blog post index. *)
val generate_project_page : Config.t -> Config.project -> (unit, Error.t) result

(** [generate_projects_directory config projects] generates [site/project.html] presenting
    a grid of project overview cards. *)
val generate_projects_directory
  :  Config.t
  -> Config.project list
  -> (unit, Error.t) result

(** [generate_home_page config projects] generates the main home page [site/index.html]
    incorporating biography constants, recent articles, and project links. *)
val generate_home_page : Config.t -> Config.project list -> (unit, Error.t) result
