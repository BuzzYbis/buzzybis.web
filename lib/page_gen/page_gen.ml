(* HTML generation for blog posts, project pages, the project directory and the home
   page. Every value that originates outside this code base (Typst output metadata,
   projects.toml, file names) is escaped before being interpolated into markup. *)

open Util.Syntax
open Util.Html
module Fs = Util.Fs

let meta_content soup meta_name =
  match Soup.select_one (Printf.sprintf "meta[name=%s]" meta_name) soup with
  | Some m -> Soup.attribute "content" m |> Option.value ~default:"" |> String.trim
  | None -> ""
;;

(* Extract a value from the first node matching [selector] and remove the node. *)
let take_node soup selector ~f =
  match Soup.select_one selector soup with
  | Some node ->
    let value = f node in
    Soup.delete node;
    value
  | None -> ""
;;

let non_empty s = not (String.equal s "")

let badge tag =
  Printf.sprintf "<span class=\"badge\">%s</span>" (escape_html (clean_tag_name tag))
;;

let clickable_badge tag =
  Printf.sprintf
    "<span class=\"badge tag-badge-clickable\">%s</span>"
    (escape_html (clean_tag_name tag))
;;

let breadcrumb crumbs =
  let render (label, href) =
    match href with
    | Some href ->
      Printf.sprintf "  <a href=\"%s\">%s</a>" (escape_html href) (escape_html label)
    | None -> Printf.sprintf "  <span>%s</span>" (escape_html label)
  in
  Printf.sprintf
    "<nav class=\"breadcrumb-nav\" aria-label=\"Breadcrumb\">\n%s\n</nav>"
    (crumbs
     |> List.map render
     |> String.concat "\n  <span class=\"breadcrumb-separator\">/</span>\n")
;;

let footer_notice ~repo_url ~footer_raw =
  if non_empty footer_raw
  then (
    let lines =
      Soup.texts (Soup.parse footer_raw) |> List.map String.trim |> List.filter non_empty
    in
    Printf.sprintf
      "<p>\n      %s\n    </p>"
      (String.concat "<br>\n      " (List.map escape_html lines)))
  else (
    let source =
      if non_empty repo_url
      then
        Printf.sprintf
          "The source of this document is available freely at <a href=\"%s\" \
           target=\"_blank\" rel=\"noopener noreferrer\">%s</a> under the CC-BY-4.0 \
           license."
          (escape_html repo_url)
          (escape_html repo_url)
      else "The source of this document is available freely under the CC-BY-4.0 license."
    in
    Printf.sprintf
      "<p>\n\
      \      %s<br>\n\
      \      Please cite this document when referencing or re-using it.\n\
      \    </p>"
      source)
;;

let format_blogpost_html
      ~project_name
      ~slug
      ?(repo_url = "")
      ?(default_tags = [])
      raw_html
  =
  let soup = Soup.parse raw_html in
  let title =
    match Soup.select_one "title" soup with
    | Some t -> Soup.leaf_text t |> Option.value ~default:"" |> String.trim
    | None -> ""
  in
  let title = if non_empty title then title else "Untitled Post" in
  let description = meta_content soup "description" in
  let meta_authors =
    match meta_content soup "author" with
    | "" -> meta_content soup "authors"
    | authors -> authors
  in
  let keywords = meta_content soup "keywords" in
  let subtitle = take_node soup ".blogpost-subtitle-raw" ~f:text_content in
  let authors_raw = take_node soup ".blogpost-authors-raw" ~f:Soup.to_string in
  let date_raw = take_node soup ".blogpost-date-raw" ~f:text_content in
  let footer_raw = take_node soup ".blogpost-footer-raw" ~f:Soup.to_string in
  let authors_html =
    if non_empty authors_raw
    then clean_authors authors_raw
    else if non_empty meta_authors
    then escape_html meta_authors
    else ""
  in
  let date =
    if non_empty date_raw
    then date_raw
    else
      Soup.texts soup
      |> String.concat " "
      |> extract_date_from_text
      |> Option.value ~default:""
  in
  let tags =
    if non_empty keywords
    then
      String.split_on_char ',' keywords |> List.map String.trim |> List.filter non_empty
    else default_tags
  in
  let tags_html = tags |> List.map clickable_badge |> String.concat " " in
  let subtitle_block =
    if non_empty subtitle
    then
      Printf.sprintf
        "\n      <p class=\"post-subtitle\" id=\"post-subtitle\">%s</p>"
        (escape_html subtitle)
    else ""
  in
  let authors_block =
    if non_empty authors_html
    then
      Printf.sprintf
        "<span class=\"author-byline\" id=\"post-authors\">By <span \
         class=\"post-author-name\" id=\"post-author-name\">%s</span></span>"
        authors_html
    else ""
  in
  let date_block =
    if non_empty date
    then
      Printf.sprintf
        "<time class=\"post-date\" id=\"post-date\" datetime=\"%s\">%s</time>"
        (escape_html date)
        (escape_html date)
    else ""
  in
  let post_header_info =
    match List.filter non_empty [ authors_block; date_block ] with
    | [] -> ""
    | items ->
      Printf.sprintf
        "<div class=\"post-header-info\">\n        %s\n      </div>"
        (String.concat
           "\n        <span class=\"meta-separator\">&middot;</span>\n        "
           items)
  in
  let pdf_url = Printf.sprintf "/project/%s/html/cached_pdf/%s.pdf" project_name slug in
  let actions_block =
    Printf.sprintf
      "<div class=\"post-header-actions\">\n\
      \        <a href=\"%s\" class=\"btn-bio btn-download-pdf\" target=\"_blank\" \
       rel=\"noopener noreferrer\" download=\"%s.pdf\" title=\"Download article as PDF\">\n\
       %s\n\
      \  <span>PDF</span>\n\
      \ </a>\n\
      \      </div>"
      (escape_html pdf_url)
      (escape_html slug)
      Svg.download_icon
  in
  let meta_row =
    Printf.sprintf
      "\n    <div class=\"post-header-meta\">\n      %s\n      %s\n    </div>"
      post_header_info
      actions_block
  in
  let tags_block =
    if non_empty tags_html
    then Printf.sprintf "\n    <div class=\"post-tags-meta\">%s</div>" tags_html
    else ""
  in
  let excerpt_block =
    if non_empty description
    then
      Printf.sprintf
        "\n    <p class=\"post-excerpt\" id=\"post-excerpt\" hidden>%s</p>"
        (escape_html description)
    else ""
  in
  set_external_link_targets soup;
  let body =
    match Soup.select_one "body" soup with
    | Some b ->
      Soup.children b |> Soup.to_list |> List.map Soup.to_string |> String.concat ""
    | None -> Soup.to_string soup
  in
  let breadcrumb_html =
    breadcrumb
      [ "Home", Some "/"
      ; "Projects", Some "/project/"
      ; project_name, Some (Printf.sprintf "/project/%s/html/" project_name)
      ; title, None
      ]
  in
  Printf.sprintf
    "%s\n\
     <article class=\"blogpost\">\n\
    \  <header class=\"post-header\">\n\
    \    <div class=\"post-title-group\">\n\
    \      <h1 class=\"post-title\" id=\"post-title\">%s</h1>%s\n\
    \    </div>%s%s%s\n\
    \  </header>\n\
    \  <div class=\"post-content\">\n\
    \    %s\n\
    \  </div>\n\
    \  <footer class=\"post-footer-notice\">\n\
    \    %s\n\
    \  </footer>\n\
     </article>"
    breadcrumb_html
    (escape_html title)
    subtitle_block
    excerpt_block
    meta_row
    tags_block
    body
    (footer_notice ~repo_url ~footer_raw)
;;

let discover_project_downloads config (project : Config.project) =
  let paths = Config.project_paths config project in
  let already_listed url =
    List.exists
      (fun (d : Config.download_item) -> String.equal d.url url)
      project.downloads
  in
  let discovered =
    Fs.list_dir paths.pdfs_dir
    |> List.sort String.compare
    |> List.filter (fun f ->
      (not (String.starts_with ~prefix:"." f)) && String.ends_with ~suffix:".pdf" f)
    |> List.filter_map (fun f ->
      let url = Printf.sprintf "%s/pdfs/%s" (Config.project_url_path project) f in
      if already_listed url
      then None
      else (
        let words =
          Filename.chop_suffix f ".pdf"
          |> String.map (fun c -> if Char.equal c '_' || Char.equal c '-' then ' ' else c)
          |> String.capitalize_ascii
        in
        Some { Config.label = Printf.sprintf "%s (PDF)" words; url }))
  in
  project.downloads @ discovered
;;

let render_project_card ~collaborators_label (project : Config.project) =
  let href = escape_html (Config.project_url_path project ^ "/html/") in
  let first_badge =
    match project.tags with
    | tag :: _ -> badge tag
    | [] -> ""
  in
  Printf.sprintf
    {|    <div class="project-card">
      <div class="project-card-header">
        <h3 class="project-card-title"><a href="%s">%s</a></h3>
        %s
      </div>
      <p class="project-card-desc">
        %s
      </p>
      <div class="project-card-footer">
        <div class="project-collaborators">
          <strong>%s:</strong> <span>%s</span>
        </div>
        <a href="%s">Project details &rarr;</a>
      </div>
    </div>|}
    href
    (escape_html project.title)
    first_badge
    (escape_html project.description)
    (escape_html collaborators_label)
    (escape_html (String.concat ", " project.collaborators))
    href
;;

let render_download_button (d : Config.download_item) =
  Printf.sprintf
    {|        <a href="%s" class="btn-bio" target="_blank" rel="noopener noreferrer" download title="Download %s">
%s
          <span>%s</span>
        </a>|}
    (escape_html d.url)
    (escape_html d.label)
    Svg.download_icon
    (escape_html d.label)
;;

(* Compiled posts are the HTML files next to the project's index.html; Soupault indexes
   exactly those pages into [#project-posts]. *)
let has_posts ~html_dir =
  Fs.list_dir html_dir
  |> List.exists (fun f ->
    String.ends_with ~suffix:".html" f
    && (not (String.equal f "index.html"))
    && not (String.starts_with ~prefix:"." f))
;;

let posts_section ~html_dir =
  if has_posts ~html_dir
  then
    {|<section class="project-posts-section">
  <h2>Articles & Blog Posts</h2>
  <p class="text-muted">Blog posts and technical notes associated with this project:</p>
  <div id="project-posts">
    <!-- Populated automatically by Soupault from the HTML DOM index -->
  </div>
</section>|}
  else
    {|<section class="project-posts-section">
  <h2>No blog or articles are linked to this project</h2>
</section>|}
;;

let generate_project_page config (project : Config.project) =
  let paths = Config.project_paths config project in
  let* () =
    Fs.mkdir_all
      [ paths.project_dir; paths.html_dir; paths.pdfs_dir; paths.cached_pdf_dir ]
  in
  let downloads = discover_project_downloads config project in
  let index_file = Filename.concat paths.html_dir "index.html" in
  let topics_block =
    match project.tags with
    | [] -> ""
    | tags ->
      Printf.sprintf
        "<div class=\"project-meta-item\"><strong>Tags</strong><div>%s</div></div>"
        (tags |> List.map badge |> String.concat " ")
  in
  let downloads_block =
    match downloads with
    | [] -> ""
    | downloads ->
      Printf.sprintf
        {|    <div class="project-meta-item">
      <strong>Downloads</strong>
      <div class="project-downloads-list">
%s
      </div>
    </div>|}
        (downloads |> List.map render_download_button |> String.concat "\n")
  in
  let html =
    Printf.sprintf
      {|%s

<section class="project-presentation">
  <div class="project-header">
    <h1 id="project-title">%s</h1>
    <p class="lead">%s</p>
  </div>

  <div class="project-meta-box">
    <div class="project-meta-item">
      <strong>Collaborators</strong>
      <span>%s</span>
    </div>
    <div class="project-meta-item">
      <strong>Repository</strong>
      <a href="%s" class="btn-bio" target="_blank" rel="noopener noreferrer" title="View repository on GitHub">
%s
        <span>GitHub</span>
      </a>
    </div>
%s
%s
  </div>
</section>

%s
|}
      (breadcrumb [ "Home", Some "/"; "Projects", Some "/project/"; project.name, None ])
      (escape_html project.title)
      (escape_html project.description)
      (escape_html (String.concat ", " project.collaborators))
      (escape_html project.repo_url)
      Svg.github_icon
      downloads_block
      topics_block
      (posts_section ~html_dir:paths.html_dir)
  in
  let* () = Fs.atomic_write_file ~path:index_file ~content:html in
  (* Legacy locations of generated indexes; they would shadow the real pages. *)
  let* () = Fs.rm_rf (Filename.concat paths.project_dir "index.html") in
  let* () = Fs.rm_rf (Filename.concat (Config.projects_dir config) "index.html") in
  Logger.info "[PROJECT PAGE] Updated %s" index_file;
  Ok ()
;;

let generate_projects_directory config projects =
  let site_project_file = Filename.concat "site" "project.html" in
  let* () = Fs.rm_rf (Filename.concat (Config.projects_dir config) "index.html") in
  let cards =
    projects
    |> List.map (render_project_card ~collaborators_label:"Collaborators")
    |> String.concat "\n\n"
  in
  let html =
    Printf.sprintf
      {|%s

<section class="projects-overview">
  <h1 id="page-title">%s</h1>
  <p class="lead">
    %s
  </p>

  <div class="project-list" id="projects-container">
%s
  </div>
</section>
|}
      (breadcrumb [ "Home", Some "/"; Content.projects_title, None ])
      (escape_html Content.projects_title)
      Content.projects_lead
      cards
  in
  let* () = Fs.atomic_write_file ~path:site_project_file ~content:html in
  Logger.info
    "[PROJECTS DIRECTORY] Updated %s (%d projects)"
    site_project_file
    (List.length projects);
  Ok ()
;;

let generate_home_page projects =
  let home_file = Filename.concat "site" "index.html" in
  let cards =
    projects
    |> List.map (render_project_card ~collaborators_label:"With")
    |> String.concat "\n\n"
  in
  let html =
    Printf.sprintf
      {|<section class="bio-section">
  <div class="bio-header">
    <h1 class="bio-title">%s</h1>
    <p class="bio-subtitle">%s</p>
  </div>

  <p class="lead">
    %s
  </p>

  <p>
    %s
  </p>

  <div class="bio-actions">
    <a href="/resume.pdf" class="btn-bio" id="btn-download-resume" target="_blank" rel="noopener noreferrer" download title="Download Resume (PDF)">
%s
      <span>Resume (PDF)</span>
    </a>
    <a href="https://github.com/%s" class="btn-bio" id="btn-github-profile" target="_blank" rel="noopener noreferrer">
%s
      <span>GitHub</span>
    </a>
  </div>
</section>

<section class="home-projects-section">
  <div class="section-header">
    <h2>Featured Projects</h2>
    <a href="/project/" class="section-more-link">View all &rarr;</a>
  </div>

  <div class="project-list" id="home-featured-projects">
%s
  </div>
</section>

<section class="home-posts-section">
  <div class="section-header">
    <h2>Recent Writing</h2>
  </div>

  <div id="home-recent-posts">
    <!-- Populated automatically by Soupault from the HTML DOM index -->
  </div>
</section>
|}
      (escape_html Content.bio_title)
      (escape_html Content.bio_subtitle)
      Content.bio_lead
      Content.bio_text
      Svg.download_icon
      Config.github_user
      Svg.github_icon
      cards
  in
  let* () = Fs.atomic_write_file ~path:home_file ~content:html in
  Logger.info "[HOME PAGE] Updated %s" home_file;
  Ok ()
;;
