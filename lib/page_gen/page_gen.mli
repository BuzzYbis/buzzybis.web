(** HTML generation for blog posts, project pages, the project directory and the home
    page. Metadata coming from Typst output or [projects.toml] is HTML-escaped; the
    article body produced by Typst is inserted as is. *)

(** [format_blogpost_html ~project_name ~slug ?repo_url ?default_tags raw_html] wraps the
    HTML document produced by Typst into the site's article layout. *)
val format_blogpost_html
  :  project_name:string
  -> slug:string
  -> ?repo_url:string
  -> ?default_tags:string list
  -> string
  -> string

(** [discover_project_downloads config project] returns [project.downloads] extended with
    every PDF found in the project's [pdfs/] directory that is not already listed. *)
val discover_project_downloads : Config.t -> Config.project -> Config.download_item list

(** [generate_project_page config project] writes the project landing page
    [html/index.html] under the project directory. *)
val generate_project_page : Config.t -> Config.project -> (unit, Error.t) result

(** [generate_projects_directory config projects] writes [site/project.html]. *)
val generate_projects_directory
  :  Config.t
  -> Config.project list
  -> (unit, Error.t) result

(** [generate_home_page projects] writes [site/index.html]. *)
val generate_home_page : Config.project list -> (unit, Error.t) result
