(* GitHub synchronization, Typst compilation, cache eviction and the fetch CLI. *)

open Util.Syntax
module Fs = Util.Fs
module Net = Util.Net
module Proc = Util.Proc
module Result_list = Util.Result_list

let cached_pdf_ttl_seconds = 10.0 *. 24.0 *. 3600.0

let parse_github_repo ~repo_url ~default_owner ~fallback_repo =
  let uri = Uri.of_string (String.trim repo_url) in
  match Uri.host uri with
  | Some ("github.com" | "www.github.com") ->
    let segments =
      String.split_on_char '/' (Uri.path uri)
      |> List.filter (fun s -> not (String.equal s ""))
    in
    (match segments with
     | owner :: repo :: _ ->
       let repo =
         if String.ends_with ~suffix:".git" repo
         then Filename.chop_suffix repo ".git"
         else repo
       in
       owner, repo
     | [] | [ _ ] -> default_owner, fallback_repo)
  | Some _ | None -> default_owner, fallback_repo
;;

let cleanup_unconfigured_projects config =
  let root = Config.projects_dir config in
  Fs.list_dir root
  |> List.iter (fun entry ->
    let full_path = Filename.concat root entry in
    if Fs.is_directory full_path && Option.is_none (Config.find_project config entry)
    then (
      Logger.info "[CLEANUP] Removing unconfigured project directory: %s" full_path;
      Logger.report
        ~context:(Printf.sprintf "cleanup_unconfigured_projects %s" full_path)
        (Fs.rm_rf full_path)))
;;

let parse_json ~context raw =
  match Yojson.Safe.from_string raw with
  | json -> Ok json
  | exception Yojson.Json_error details ->
    Error (Error.json_parse_error ~context ~raw details)
;;

let get_remote_blog_sha ~owner ~repo =
  let url =
    Printf.sprintf
      "https://api.github.com/repos/%s/%s/commits?path=blog&per_page=1"
      owner
      repo
  in
  let* body = Net.http_get url in
  let+ json = parse_json ~context:(Printf.sprintf "commits for %s/%s" owner repo) body in
  match json with
  | `List (`Assoc fields :: _) ->
    (match List.assoc_opt "sha" fields with
     | Some (`String sha) -> Some sha
     | Some _ | None -> None)
  | _ -> None
;;

let clean_expired_cached_pdfs config project =
  let paths = Config.project_paths config project in
  let dir = paths.cached_pdf_dir in
  if Fs.is_directory dir
  then (
    let json_path = Filename.concat dir ".downloads.json" in
    let timestamps =
      Fs.read_json_assoc json_path
      |> List.filter_map (fun (name, value) ->
        match value with
        | `Float t -> Some (name, t)
        | `Int t -> Some (name, float_of_int t)
        | _ -> None)
    in
    let now = Unix.time () in
    let kept =
      Fs.list_dir dir
      |> List.filter (String.ends_with ~suffix:".pdf")
      |> List.filter_map (fun file ->
        let full_path = Filename.concat dir file in
        let last_access =
          match List.assoc_opt file timestamps with
          | Some t -> t
          | None ->
            (try (Unix.stat full_path).Unix.st_mtime with
             | Unix.Unix_error _ -> now)
        in
        if now -. last_access > cached_pdf_ttl_seconds
        then (
          Logger.info
            "  [CACHE EXPIRED] Removing %s from %s/html/cached_pdf"
            file
            project.name;
          Logger.report
            ~context:(Printf.sprintf "expire cached pdf %s" full_path)
            (Fs.rm_rf full_path);
          None)
        else Some (file, `Float last_access))
    in
    Logger.report
      ~context:"clean_expired_cached_pdfs"
      (Fs.write_json ~path:json_path (`Assoc kept)))
;;

(* [site/project] is a symlink to the external projects directory so that Soupault and
   the local server see the generated pages. *)
let ensure_clean_repo_site config =
  let site_project = Filename.concat (Sys.getcwd ()) (Filename.concat "site" "project") in
  let* () = Fs.mkdir_p (Config.projects_dir config) in
  (* Resolved again now that the directory exists, so the path is canonical. *)
  let projects_dir = Config.projects_dir config in
  Logger.info "[CONFIG] Projects directory configured at: %s" projects_dir;
  let link () = Fs.symlink_force ~src:projects_dir ~dest:site_project in
  match Fs.kind site_project with
  | Some Unix.S_LNK -> Ok ()
  | Some _ ->
    Logger.info
      "[MIGRATION] Found old directory at %s, replacing with symlink to %s"
      site_project
      projects_dir;
    let* () = Fs.rm_rf site_project in
    link ()
  | None ->
    Logger.info "[SETUP] Creating symlink: %s -> %s" site_project projects_dir;
    link ()
;;

let download_repo_blog_files ~temp_blog files =
  Result_list.iter
    (fun (file_name, download_url) ->
       let* file_name = Fs.check_basename file_name in
       Logger.info "  [+] Downloading %s ..." file_name;
       Net.download_file ~url:download_url ~dest:(Filename.concat temp_blog file_name))
    files
;;

let compile_typ_posts
      ~temp_blog
      ~temp_root
      ~html_dir
      ~(project : Config.project)
      typ_files
  =
  Result_list.map
    (fun typ_file ->
       let src = Filename.concat temp_blog typ_file in
       let slug = Filename.chop_suffix typ_file ".typ" in
       let out_html_name = slug ^ ".html" in
       let out_html_path = Filename.concat html_dir out_html_name in
       Logger.info "  [*] Compiling %s to %s ..." typ_file out_html_name;
       let* raw_html =
         Typst.compile_html ~root:temp_root ~repo_url:project.repo_url ~src
       in
       let content =
         Page_gen.format_blogpost_html
           ~project_name:project.name
           ~slug
           ~repo_url:project.repo_url
           ~default_tags:project.tags
           raw_html
       in
       let+ () = Fs.atomic_write_file ~path:out_html_path ~content in
       Logger.info "  [✔] Generated %s" out_html_path;
       out_html_name)
    typ_files
;;

let copy_companion_assets ~temp_blog ~html_dir files =
  files
  |> List.filter (fun f -> not (String.ends_with ~suffix:".typ" f))
  |> List.iter (fun f ->
    let src = Filename.concat temp_blog f in
    if Sys.file_exists src
    then (
      Logger.info "  [+] Copying companion asset: %s" f;
      Logger.report
        ~context:(Printf.sprintf "copy asset %s" f)
        (Fs.cp_r ~src ~dest:(Filename.concat html_dir f))))
;;

let remove_matching ~dir ~log_label pred =
  Fs.list_dir dir
  |> List.filter pred
  |> List.iter (fun entry ->
    Logger.info "  [-] Removing %s: %s" log_label entry;
    let path = Filename.concat dir entry in
    Logger.report ~context:(Printf.sprintf "remove %s %s" log_label path) (Fs.rm_rf path))
;;

let clean_stale_html_and_legacy ~(paths : Config.project_paths) keep_html =
  remove_matching ~dir:paths.html_dir ~log_label:"stale HTML" (fun f ->
    String.ends_with ~suffix:".html" f && not (List.exists (String.equal f) keep_html));
  remove_matching
    ~dir:paths.project_dir
    ~log_label:"stray file from project root"
    (fun f -> String.ends_with ~suffix:".html" f || String.ends_with ~suffix:".pdf" f)
;;

let invalidate_cached_pdfs dir =
  remove_matching ~dir ~log_label:"cached PDF" (fun (_ : string) -> true)
;;

let parse_contents_listing ~owner ~repo json =
  let endpoint = Printf.sprintf "%s/%s" owner repo in
  match json with
  | `List items ->
    Ok
      (List.filter_map
         (function
           | `Assoc fields ->
             (match
                ( List.assoc_opt "type" fields
                , List.assoc_opt "name" fields
                , List.assoc_opt "download_url" fields )
              with
              | Some (`String "file"), Some (`String name), Some (`String url) ->
                Some (name, url)
              | _ -> None)
           | _ -> None)
         items)
  | `Assoc fields ->
    (match List.assoc_opt "message" fields with
     | Some (`String "Not Found") ->
       Logger.info
         "  [INFO] Repo '%s' does not have a 'blog/' directory yet on GitHub."
         endpoint;
       Ok []
     | Some (`String msg) -> Error (Error.github_api_failed ~endpoint msg)
     | Some _ | None ->
       Error (Error.github_api_failed ~endpoint "Unknown response format"))
  | _ -> Error (Error.github_api_failed ~endpoint "Expected JSON array or object")
;;

type outcome =
  { rebuilt : bool
  ; new_sha : string option
  }

let fetch_and_compile config ~state ~force_rebuild (project : Config.project) =
  let owner, repo =
    parse_github_repo
      ~repo_url:project.repo_url
      ~default_owner:Config.github_user
      ~fallback_repo:project.name
  in
  Logger.info "[%s] Checking repository: %s/%s ..." project.name owner repo;
  let remote_sha =
    match get_remote_blog_sha ~owner ~repo with
    | Ok sha -> sha
    | Error err ->
      Logger.log_error
        ~context:(Printf.sprintf "get_remote_blog_sha for %s" project.name)
        err;
      None
  in
  let local_sha = List.assoc_opt project.name state in
  let needs_rebuild =
    force_rebuild
    ||
    match remote_sha, local_sha with
    | Some remote, Some local -> not (String.equal remote local)
    | Some _, None -> true
    | None, _ -> false
  in
  let paths = Config.project_paths config project in
  let* () =
    Fs.mkdir_all
      [ paths.project_dir; paths.html_dir; paths.pdfs_dir; paths.cached_pdf_dir ]
  in
  if not needs_rebuild
  then (
    Logger.info
      "  [SKIP] Up-to-date (SHA: %s)"
      (Option.value ~default:"unknown" local_sha);
    Ok { rebuilt = false; new_sha = None })
  else (
    Logger.info "  [FETCH] Downloading file manifest from GitHub API...";
    let url =
      Printf.sprintf "https://api.github.com/repos/%s/%s/contents/blog" owner repo
    in
    let* body = Net.http_get url in
    let* json =
      parse_json ~context:(Printf.sprintf "contents for %s/%s" owner repo) body
    in
    let* files = parse_contents_listing ~owner ~repo json in
    match files with
    | [] ->
      Logger.info "  [INFO] No files found in %s/%s/blog/" owner repo;
      Ok { rebuilt = false; new_sha = None }
    | files ->
      let temp_root = Filename.concat Config.fetch_tmp_dir project.name in
      let temp_blog = Filename.concat temp_root "blog" in
      let* () = Fs.mkdir_p temp_blog in
      let template_source =
        Filename.concat (Sys.getcwd ()) (Filename.concat "templates" "template.typ")
      in
      let temp_template = Filename.concat temp_root "template.typ" in
      if not (Sys.file_exists temp_template)
      then
        Logger.report
          ~context:"symlink template.typ"
          (Fs.symlink_force ~src:template_source ~dest:temp_template);
      let* () = download_repo_blog_files ~temp_blog files in
      let names = List.map fst files in
      let typ_files = List.filter (String.ends_with ~suffix:".typ") names in
      let* generated =
        compile_typ_posts
          ~temp_blog
          ~temp_root
          ~html_dir:paths.html_dir
          ~project
          typ_files
      in
      copy_companion_assets ~temp_blog ~html_dir:paths.html_dir names;
      clean_stale_html_and_legacy ~paths ("index.html" :: generated);
      if Option.is_some remote_sha then invalidate_cached_pdfs paths.cached_pdf_dir;
      Ok { rebuilt = true; new_sha = remote_sha })
;;

let generate_pages config =
  List.iter
    (fun (project : Config.project) ->
       Logger.report
         ~context:(Printf.sprintf "generate_project_page for %s" project.name)
         (Page_gen.generate_project_page config project))
    config.projects;
  Logger.report
    ~context:"generate_projects_directory"
    (Page_gen.generate_projects_directory config config.projects);
  Logger.report
    ~context:"generate_home_page"
    (Page_gen.generate_home_page config.projects)
;;

let prepare_site config =
  Logger.report ~context:"ensure_clean_repo_site" (ensure_clean_repo_site config);
  List.iter (clean_expired_cached_pdfs config) config.projects
;;

let run_full_build () =
  Logger.info "Triggering Soupault build to incorporate new blogposts...";
  match Proc.run_checked "make" [ "build" ] with
  | Ok (_ : Proc.output) -> Logger.info "[✔] Full build completed successfully."
  | Error err -> Logger.log_error ~context:"Soupault build" err
;;

(* Returns the updated fetch state. *)
let run_sync config ~state ~force_rebuild =
  Logger.info "=== BuzzYbis Project & Blog Sync ===";
  Logger.info "Reading configuration from %s..." Config.config_file;
  match config.Config.projects with
  | [] ->
    Logger.warn
      "No projects found in %s. Please add your repositories there."
      Config.config_file;
    state
  | projects ->
    prepare_site config;
    cleanup_unconfigured_projects config;
    let any_rebuilt, state =
      List.fold_left
        (fun (any_rebuilt, state) (project : Config.project) ->
           match fetch_and_compile config ~state ~force_rebuild project with
           | Ok { rebuilt; new_sha } ->
             let state =
               match new_sha with
               | Some sha -> (project.name, sha) :: List.remove_assoc project.name state
               | None -> state
             in
             any_rebuilt || rebuilt, state
           | Error err ->
             Logger.log_error
               ~context:(Printf.sprintf "fetch_and_compile for %s" project.name)
               err;
             any_rebuilt, state)
        (false, state)
        projects
    in
    Logger.report ~context:"save_fetch_state" (Config.save_fetch_state config state);
    generate_pages config;
    if any_rebuilt
    then run_full_build ()
    else Logger.info "[✔] Everything is up-to-date. No rebuild needed.";
    state
;;

let main () =
  Logger.init ();
  let force = ref false
  and watch = ref false
  and pages_only = ref false
  and poll = ref None in
  let specs =
    Arg.align
      [ "--force", Arg.Set force, " Refetch and recompile even if commit SHAs match"
      ; "-f", Arg.Set force, " Alias for --force"
      ; ( "--watch"
        , Arg.Set watch
        , " Poll periodically and rebuild when a repository changes" )
      ; "-w", Arg.Set watch, " Alias for --watch"
      ; ( "--pages-only"
        , Arg.Set pages_only
        , " Only regenerate project, directory and home pages" )
      ; ( "--poll"
        , Arg.Int (fun n -> poll := Some n)
        , "SECONDS Polling interval (implies --watch)" )
      ]
  in
  let usage = "Usage: fetch [--force] [--watch] [--pages-only] [--poll SECONDS]" in
  Arg.parse specs (fun arg -> raise (Arg.Bad ("unexpected argument: " ^ arg))) usage;
  let config =
    match Config.load Config.config_file with
    | Ok config -> config
    | Error err ->
      Logger.log_error ~context:"Config.load" err;
      exit 1
  in
  if !pages_only
  then (
    prepare_site config;
    generate_pages config)
  else (
    let state = Config.load_fetch_state config in
    match !watch, !poll with
    | false, None ->
      ignore (run_sync config ~state ~force_rebuild:!force : (string * string) list)
    | _ ->
      let interval = max 1 (Option.value !poll ~default:config.poll_interval) in
      Logger.info "BuzzYbis Watch Daemon started (checking every %d seconds)." interval;
      Logger.info "Press Ctrl+C to stop.";
      Sys.set_signal
        Sys.sigint
        (Sys.Signal_handle
           (fun (_ : int) ->
             Logger.info "Stopping watch daemon.";
             exit 0));
      let rec loop state =
        let state = run_sync config ~state ~force_rebuild:!force in
        Unix.sleep interval;
        loop state
      in
      loop state)
;;
