(* HTML page generation for projects, articles, directory, and home page *)

open Config
include Util.Syntax
include Util.Html
module Fs = Util.Fs

let strip_typst_export_warnings html =
  let re = Str.regexp "warning: html export is under active development[^\000]*" in
  Str.global_replace re "" html
;;

let format_blogpost_html
  ~project_name
  ~slug
  ?(repo_url = "")
  ?(default_tags = [])
  raw_html
  =
  try
    let clean_html = strip_typst_export_warnings raw_html in
    let soup = Soup.parse clean_html in
    let title =
      match Soup.(soup $? "title") with
      | Some t -> Soup.leaf_text t |> Option.value ~default:"Untitled Post" |> String.trim
      | None -> "Untitled Post"
    in
    let description =
      match Soup.(soup $? "meta[name=description]") with
      | Some m -> Soup.attribute "content" m |> Option.value ~default:"" |> String.trim
      | None -> ""
    in
    let meta_authors =
      match Soup.(soup $? "meta[name=author]") with
      | Some m -> Soup.attribute "content" m |> Option.value ~default:"" |> String.trim
      | None ->
        (match Soup.(soup $? "meta[name=authors]") with
         | Some m -> Soup.attribute "content" m |> Option.value ~default:"" |> String.trim
         | None -> "")
    in
    let keywords =
      match Soup.(soup $? "meta[name=keywords]") with
      | Some m -> Soup.attribute "content" m |> Option.value ~default:"" |> String.trim
      | None -> ""
    in
    (* Extract and remove raw subtitle div from soup if present *)
    let subtitle_raw =
      match Soup.(soup $? ".blogpost-subtitle-raw") with
      | Some node ->
        let s = Soup.texts node |> String.concat "" |> String.trim in
        Soup.delete node;
        s
      | None -> ""
    in
    let subtitle = clean_subtitle subtitle_raw in
    (* Extract and remove raw authors div from soup if present *)
    let authors_raw =
      match Soup.(soup $? ".blogpost-authors-raw") with
      | Some node ->
        let s = Soup.to_string node in
        Soup.delete node;
        s
      | None -> ""
    in
    let authors_html =
      if not (String.equal authors_raw "")
      then clean_authors authors_raw
      else if not (String.equal meta_authors "")
      then escape_html meta_authors
      else ""
    in
    (* Extract and remove raw date div from soup if present *)
    let date_raw =
      match Soup.(soup $? ".blogpost-date-raw") with
      | Some node ->
        let s = Soup.texts node |> String.concat "" |> String.trim in
        Soup.delete node;
        s
      | None -> ""
    in
    let date =
      if not (String.equal date_raw "")
      then date_raw
      else (
        let body_text = Soup.texts soup |> String.concat " " in
        match extract_date_from_text body_text with
        | Some d -> d
        | None -> "")
    in
    (* Extract and remove raw footer div from soup if present *)
    let footer_raw =
      match Soup.(soup $? ".blogpost-footer-raw") with
      | Some node ->
        let s = Soup.to_string node in
        Soup.delete node;
        s
      | None -> ""
    in
    let footer_notice_content =
      if not (String.equal footer_raw "")
      then (
        let footer_soup = Soup.parse footer_raw in
        let lines =
          Soup.texts footer_soup
          |> List.map String.trim
          |> List.filter (fun s -> not (String.equal s ""))
        in
        Printf.sprintf "<p>\n      %s\n    </p>" (String.concat "<br>\n      " lines))
      else (
        let repo_link =
          if not (String.equal repo_url "")
          then
            Printf.sprintf
              "The source of this document is available freely at <a href=\"%s\" \
               target=\"_blank\" rel=\"noopener noreferrer\">%s</a> under the CC-BY-4.0 \
               license."
              (escape_html repo_url)
              (escape_html repo_url)
          else
            "The source of this document is available freely under the CC-BY-4.0 license."
        in
        Printf.sprintf
          "<p>\n\
          \      %s<br>\n\
          \      Please cite this document when referencing or re-using it.\n\
          \    </p>"
          repo_link)
    in
    let breadcrumb_html =
      Printf.sprintf
        "<nav class=\"breadcrumb-nav\" aria-label=\"Breadcrumb\">\n\
        \  <a href=\"/\">Home</a>\n\
        \  <span class=\"breadcrumb-separator\">/</span>\n\
        \  <a href=\"/project/\">Projects</a>\n\
        \  <span class=\"breadcrumb-separator\">/</span>\n\
        \  <a href=\"/project/%s/html/\">%s</a>\n\
        \  <span class=\"breadcrumb-separator\">/</span>\n\
        \  <span>%s</span>\n\
         </nav>"
        project_name
        project_name
        title
    in
    let tags =
      if not (String.equal keywords "")
      then
        String.split_on_char ',' keywords
        |> List.map String.trim
        |> List.filter (fun s -> not (String.equal s ""))
        |> List.map clean_tag_name
      else default_tags
    in
    let render_tag_clickable t =
      Printf.sprintf
        "<span class=\"badge tag-badge-clickable\">%s</span>"
        (clean_tag_name t)
    in
    let tags_html = tags |> List.map render_tag_clickable |> String.concat " " in
    let subtitle_block =
      if not (String.equal subtitle "")
      then
        Printf.sprintf
          "\n      <p class=\"post-subtitle\" id=\"post-subtitle\">%s</p>"
          (escape_html subtitle)
      else ""
    in
    let authors_block =
      if not (String.equal authors_html "")
      then
        Printf.sprintf
          "<span class=\"author-byline\" id=\"post-authors\">By <span \
           class=\"post-author-name\" id=\"post-author-name\">%s</span></span>"
          authors_html
      else ""
    in
    let date_block =
      if not (String.equal date "")
      then
        Printf.sprintf
          "<time class=\"post-date\" id=\"post-date\" datetime=\"%s\">%s</time>"
          (escape_html date)
          (escape_html date)
      else ""
    in
    let info_items =
      List.filter (fun s -> not (String.equal s "")) [ authors_block; date_block ]
    in
    let post_header_info =
      match info_items with
      | [] -> ""
      | _ ->
        Printf.sprintf
          "<div class=\"post-header-info\">\n        %s\n      </div>"
          (String.concat
             "\n        <span class=\"meta-separator\">&middot;</span>\n        "
             info_items)
    in
    let pdf_url = Printf.sprintf "/project/%s/html/cached_pdf/%s.pdf" project_name slug in
    let pdf_btn_html =
      Printf.sprintf
        "<a href=\"%s\" class=\"btn-bio btn-download-pdf\" target=\"_blank\" \
         rel=\"noopener noreferrer\" download=\"%s.pdf\" title=\"Download article as \
         PDF\">\n\
         %s\n\
        \  <span>PDF</span>\n\
         </a>"
        pdf_url
        slug
        Svg.download_icon
    in
    let actions_block =
      Printf.sprintf
        "<div class=\"post-header-actions\">\n        %s\n      </div>"
        pdf_btn_html
    in
    let meta_row =
      if String.equal post_header_info "" && String.equal actions_block ""
      then ""
      else
        Printf.sprintf
          "\n    <div class=\"post-header-meta\">\n      %s\n      %s\n    </div>"
          post_header_info
          actions_block
    in
    let tags_block =
      if not (String.equal tags_html "")
      then Printf.sprintf "\n    <div class=\"post-tags-meta\">%s</div>" tags_html
      else ""
    in
    let excerpt_block =
      if not (String.equal description "")
      then
        Printf.sprintf
          "\n\
          \    <p class=\"post-excerpt\" id=\"post-excerpt\" style=\"display: \
           none;\">%s</p>"
          (escape_html description)
      else ""
    in
    let add_external_target a =
      match Soup.attribute "href" a with
      | Some h
        when String.starts_with ~prefix:"http://" h
             || String.starts_with ~prefix:"https://" h ->
        Soup.set_attribute "target" "_blank" a;
        Soup.set_attribute "rel" "noopener noreferrer" a
      | Some _ | None -> ()
    in
    Soup.iter add_external_target (Soup.select "a" soup);
    let final_body =
      match Soup.(soup $? "body") with
      | Some b ->
        Soup.children b |> Soup.to_list |> List.map Soup.to_string |> String.concat ""
      | None -> Soup.to_string soup
    in
    Ok
      (Printf.sprintf
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
         final_body
         footer_notice_content)
  with
  | exn -> Error (Error.html_parse_failed ~context:slug (Printexc.to_string exn))
;;

let discover_project_downloads (config : Config.t) (project : Config.project) =
  let pdir = Config.get_projects_dir config in
  let pdfs_dir = Filename.concat (Filename.concat pdir project.name) "pdfs" in
  if Sys.file_exists pdfs_dir && Sys.is_directory pdfs_dir
  then (
    let files = Sys.readdir pdfs_dir |> Array.to_list |> List.sort String.compare in
    let check_and_add_pdf f =
      if (not (String.starts_with ~prefix:"." f)) && String.ends_with ~suffix:".pdf" f
      then (
        let url = Printf.sprintf "/project/%s/pdfs/%s" project.name f in
        if not
             (List.exists
                (fun (d : Config.download_item) -> String.equal d.url url)
                project.downloads)
        then (
          let basename = Filename.chop_suffix f ".pdf" in
          let formatted_title =
            String.map
              (fun c -> if Char.equal c '_' || Char.equal c '-' then ' ' else c)
              basename
            |> String.capitalize_ascii
          in
          let label = Printf.sprintf "%s (PDF)" formatted_title in
          project.downloads <- project.downloads @ [ { label; url } ]))
    in
    List.iter check_and_add_pdf files)
;;

let render_project_card ~collaborators_label (project : Config.project) =
  let badge =
    match project.tags with
    | t :: _ -> Printf.sprintf "<span class=\"badge\">%s</span>" (clean_tag_name t)
    | [] -> ""
  in
  let collabs = String.concat ", " project.collaborators in
  Printf.sprintf
    {|    <div class="project-card">
      <div class="project-card-header">
        <h3 class="project-card-title"><a href="/project/%s/html/">%s</a></h3>
        %s
      </div>
      <p class="project-card-desc">
        %s
      </p>
      <div class="project-card-footer">
        <div class="project-collaborators">
          <strong>%s:</strong> <span>%s</span>
        </div>
        <a href="/project/%s/html/">Project details &rarr;</a>
      </div>
    </div>|}
    project.name
    project.title
    badge
    project.description
    collaborators_label
    collabs
    project.name
;;

let generate_project_page (config : Config.t) (project : Config.project) =
  let project_dir = Filename.concat (Config.get_projects_dir config) project.name in
  let html_dir = Filename.concat project_dir "html" in
  let pdfs_dir = Filename.concat project_dir "pdfs" in
  let cached_pdf_dir = Filename.concat html_dir "cached_pdf" in
  let* () = Fs.mkdir_p project_dir in
  let* () = Fs.mkdir_p html_dir in
  let* () = Fs.mkdir_p pdfs_dir in
  let* () = Fs.mkdir_p cached_pdf_dir in
  discover_project_downloads config project;
  let index_file = Filename.concat html_dir "index.html" in
  let collabs_str = String.concat ", " project.collaborators in
  let render_badge t =
    Printf.sprintf "<span class=\"badge\">%s</span>" (clean_tag_name t)
  in
  let tags_html = project.tags |> List.map render_badge |> String.concat " " in
  let topics_block =
    if not (String.equal tags_html "")
    then
      Printf.sprintf
        "<div class=\"project-meta-item\"><strong>Tags</strong><div>%s</div></div>"
        tags_html
    else ""
  in
  let render_download_btn (d : Config.download_item) =
    Printf.sprintf
      {|        <a href="%s" class="btn-bio" target="_blank" rel="noopener noreferrer" download title="Download %s">
%s
          <span>%s</span>
        </a>|}
      (escape_html d.url)
      (escape_html d.label)
      Svg.download_icon
      (escape_html d.label)
  in
  let downloads_html =
    project.downloads |> List.map render_download_btn |> String.concat "\n"
  in
  let downloads_block =
    if not (String.equal downloads_html "")
    then
      Printf.sprintf
        {|    <div class="project-meta-item">
      <strong>Downloads</strong>
      <div class="project-downloads-list">
%s
      </div>
    </div>|}
        downloads_html
    else ""
  in
  let html =
    Printf.sprintf
      {|<nav class="breadcrumb-nav" aria-label="Breadcrumb">
  <a href="/">Home</a>
  <span class="breadcrumb-separator">/</span>
  <a href="/project/">Projects</a>
  <span class="breadcrumb-separator">/</span>
  <span>%s</span>
</nav>

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

<section class="project-posts-section">
  <h2>Articles & Blog Posts</h2>
  <p class="text-muted">Blog posts and technical notes associated with this project:</p>
  <div id="project-posts">
    <!-- Populated automatically by Soupault from the HTML DOM index -->
  </div>
</section>
|}
      project.name
      project.title
      project.description
      collabs_str
      project.repo_url
      Svg.github_icon
      downloads_block
      topics_block
  in
  let* () = Fs.atomic_write_file ~path:index_file ~content:html in
  let root_index_file = Filename.concat project_dir "index.html" in
  if Sys.file_exists root_index_file
  then ignore (Fs.rm_rf root_index_file : (unit, Error.t) result);
  let pdir_index_file = Filename.concat (Config.get_projects_dir config) "index.html" in
  if Sys.file_exists pdir_index_file
  then ignore (Fs.rm_rf pdir_index_file : (unit, Error.t) result);
  Logger.info "[PROJECT PAGE] Updated %s" index_file;
  Ok ()
;;

let generate_projects_directory (config : Config.t) projects =
  let pdir = Config.get_projects_dir config in
  let pdir_index_file = Filename.concat pdir "index.html" in
  let site_project_file = Filename.concat "site" "project.html" in
  if Sys.file_exists pdir_index_file
  then ignore (Fs.rm_rf pdir_index_file : (unit, Error.t) result);
  let cards =
    projects
    |> List.map (render_project_card ~collaborators_label:"Collaborators")
    |> String.concat "\n\n"
  in
  let html =
    Printf.sprintf
      {|<nav class="breadcrumb-nav" aria-label="Breadcrumb">
  <a href="/">Home</a>
  <span class="breadcrumb-separator">/</span>
  <span>%s</span>
</nav>

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
      Content.projects_title
      Content.projects_title
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

let generate_home_page _config projects =
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
    <a href="https://github.com/BuzzYbis" class="btn-bio" id="btn-github-profile" target="_blank" rel="noopener noreferrer">
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
    <!-- HOME_FEATURED_PROJECTS_START -->
%s
    <!-- HOME_FEATURED_PROJECTS_END -->
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
      Content.bio_title
      Content.bio_subtitle
      Content.bio_lead
      Content.bio_text
      Svg.download_icon
      Svg.github_icon
      cards
  in
  let* () = Fs.atomic_write_file ~path:home_file ~content:html in
  Logger.info "[HOME PAGE] Updated %s from Content constants" home_file;
  Ok ()
;;
