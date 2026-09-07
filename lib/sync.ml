(* Remote repository synchronization, Typst compilation, cache eviction, and fetch CLI *)

open Config
include Util.Syntax
module Fs = Util.Fs
module Net = Util.Net

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
       let clean_repo =
         if String.ends_with ~suffix:".git" repo
         then Filename.chop_suffix repo ".git"
         else repo
       in
       owner, clean_repo
     | [] | [ _ ] -> default_owner, fallback_repo)
  | Some _ | None -> default_owner, fallback_repo
;;

let cleanup_unconfigured_projects (config : Config.t) =
  let project_root = Config.get_projects_dir config in
  if Sys.file_exists project_root && Sys.is_directory project_root
  then (
    let entries = Sys.readdir project_root in
    let configured_names =
      List.map (fun (project : project) -> project.name) config.projects
    in
    let check_and_clean entry =
      let full_path = Filename.concat project_root entry in
      if Sys.is_directory full_path
         && not (List.exists (String.equal entry) configured_names)
      then (
        Logger.info "[CLEANUP] Removing unconfigured project directory: %s" full_path;
        match Fs.rm_rf full_path with
        | Ok () -> ()
        | Error err ->
          Logger.log_error
            ~context:(Printf.sprintf "cleanup_unconfigured_projects %s" full_path)
            err)
    in
    Array.iter check_and_clean entries)
;;

let get_remote_blog_sha ~owner ~repo =
  let url =
    Printf.sprintf
      "https://api.github.com/repos/%s/%s/commits?path=blog&per_page=1"
      owner
      repo
  in
  let* json_str = Net.http_get url in
  try
    let json = Yojson.Safe.from_string json_str in
    match json with
    | `List (item :: _) ->
      (match item with
       | `Assoc fields ->
         (match List.assoc_opt "sha" fields with
          | Some (`String sha) -> Ok (Some sha)
          | Some _ | None -> Ok None)
       | _ -> Ok None)
    | `List [] -> Ok None
    | _ -> Ok None
  with
  | exn ->
    Error
      (Error.json_parse_error
         ~context:(Printf.sprintf "commits for %s/%s" owner repo)
         ~raw:json_str
         (Printexc.to_string exn))
;;

let clean_expired_cached_pdfs (config : Config.t) (project : project) =
  let project_dir = Filename.concat (Config.get_projects_dir config) project.name in
  let cached_pdf_dir =
    Filename.concat (Filename.concat project_dir "html") "cached_pdf"
  in
  if Sys.file_exists cached_pdf_dir && Sys.is_directory cached_pdf_dir
  then (
    let json_path = Filename.concat cached_pdf_dir ".downloads.json" in
    let download_timestamps =
      if Sys.file_exists json_path
      then (
        try
          match Yojson.Safe.from_file json_path with
          | `Assoc items ->
            List.filter_map
              (fun (k, v) ->
                match v with
                | `Float f -> Some (k, f)
                | `Int i -> Some (k, float_of_int i)
                | _ -> None)
              items
          | _ -> []
        with
        | Sys_error _ | Yojson.Json_error _ -> [])
      else []
    in
    let now = Unix.time () in
    let ten_days_seconds = 10.0 *. 24.0 *. 3600.0 in
    let updated_timestamps = ref [] in
    let files = Sys.readdir cached_pdf_dir in
    let check_pdf f =
      if String.ends_with ~suffix:".pdf" f
      then (
        let full_path = Filename.concat cached_pdf_dir f in
        let last_access =
          match List.assoc_opt f download_timestamps with
          | Some t -> t
          | None ->
            (try (Unix.stat full_path).Unix.st_mtime with
             | Unix.Unix_error _ -> now)
        in
        if now -. last_access > ten_days_seconds
        then (
          Logger.info
            "  [CACHE EXPIRED] Removing %s from %s/html/cached_pdf"
            f
            project.name;
          match Fs.rm_rf full_path with
          | Ok () -> ()
          | Error err ->
            Logger.log_error
              ~context:(Printf.sprintf "expire cached pdf %s" full_path)
              err)
        else updated_timestamps := (f, `Float last_access) :: !updated_timestamps)
    in
    Array.iter check_pdf files;
    let tmp_path = Printf.sprintf "%s.tmp.%d" json_path (Unix.getpid ()) in
    try
      Yojson.Safe.to_file tmp_path (`Assoc !updated_timestamps);
      Sys.rename tmp_path json_path
    with
    | exn ->
      (try Sys.remove tmp_path with
       | Sys_error _ | Unix.Unix_error _ -> ());
      Logger.log_error
        ~context:"clean_expired_cached_pdfs"
        (Error.json_write_error ~path:json_path (Printexc.to_string exn)))
;;

let ensure_clean_repo_site (config : Config.t) =
  let cwd = Sys.getcwd () in
  let default_site_proj = Filename.concat cwd (Filename.concat "site" "project") in
  let abs_projects_dir = Config.get_projects_dir config in
  Logger.info "[CONFIG] Projects directory configured at: %s" abs_projects_dir;
  let* () = Fs.mkdir_p abs_projects_dir in
  if Sys.file_exists default_site_proj
  then (
    let is_link =
      try (Unix.lstat default_site_proj).Unix.st_kind = Unix.S_LNK with
      | Unix.Unix_error _ -> false
    in
    if is_link
    then Ok ()
    else (
      Logger.info
        "[MIGRATION] Found old directory at %s, replacing with symlink to %s"
        default_site_proj
        abs_projects_dir;
      let* () = Fs.rm_rf default_site_proj in
      Fs.symlink_force ~src:abs_projects_dir ~dest:default_site_proj))
  else (
    Logger.info "[SETUP] Creating symlink: %s -> %s" default_site_proj abs_projects_dir;
    Fs.symlink_force ~src:abs_projects_dir ~dest:default_site_proj)
;;

let download_repo_blog_files ~temp_blog files =
  let rec loop = function
    | [] -> Ok ()
    | (file_name, download_url) :: rest ->
      let dest = Filename.concat temp_blog file_name in
      Logger.info "  [+] Downloading %s ..." file_name;
      let* () = Net.download_file ~url:download_url ~dest in
      loop rest
  in
  loop files
;;

let compile_typ_posts ~temp_blog ~temp_root ~html_dir ~project font_arg typ_files =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | (typ_file, _) :: rest ->
      let src = Filename.concat temp_blog typ_file in
      let base_name = Filename.chop_suffix typ_file ".typ" in
      let out_html_name = base_name ^ ".html" in
      let out_html_path = Filename.concat html_dir out_html_name in
      Logger.info "  [*] Compiling %s to %s ..." typ_file out_html_name;
      let err_file = Filename.temp_file "typst" ".err" in
      let cmd =
        Printf.sprintf
          "typst compile --root %s %s--input repo_url=%s --input format=html --features \
           html -f html %s - 2>%s"
          (Filename.quote temp_root)
          font_arg
          (Filename.quote project.repo_url)
          (Filename.quote src)
          (Filename.quote err_file)
      in
      let* status, raw_output = Net.run_cmd cmd in
      let err_output =
        if Sys.file_exists err_file
        then (
          let content =
            try In_channel.with_open_text err_file In_channel.input_all with
            | Sys_error _ -> ""
          in
          (try Sys.remove err_file with
           | Sys_error _ | Unix.Unix_error _ -> ());
          content)
        else ""
      in
      (match status with
       | Unix.WEXITED 0 ->
         let* formatted =
           Page_gen.format_blogpost_html
             ~project_name:project.name
             ~slug:base_name
             ~repo_url:project.repo_url
             ~default_tags:project.tags
             raw_output
         in
         let* () = Fs.atomic_write_file ~path:out_html_path ~content:formatted in
         Logger.info "  [✔] Generated %s" out_html_path;
         loop (out_html_name :: acc) rest
       | Unix.WEXITED code ->
         Error (Error.typst_compile_failed ~src ~exit_code:code ~output:err_output)
       | Unix.WSIGNALED signum ->
         Error
           (Error.typst_compile_failed ~src ~exit_code:(128 + signum) ~output:err_output)
       | Unix.WSTOPPED _ ->
         Error (Error.typst_compile_failed ~src ~exit_code:1 ~output:err_output))
  in
  loop [] typ_files
;;

let copy_companion_assets ~temp_blog ~html_dir files =
  let non_typ =
    List.filter (fun (f, _) -> not (String.ends_with ~suffix:".typ" f)) files
  in
  let copy_asset (f, _) =
    let src = Filename.concat temp_blog f in
    let dest = Filename.concat html_dir f in
    let dest_dir = Filename.dirname dest in
    ignore (Fs.mkdir_p dest_dir : (unit, Error.t) result);
    if Sys.file_exists src
    then (
      Logger.info "  [+] Copying companion asset: %s" f;
      match Fs.cp_r ~src ~dest with
      | Ok () -> ()
      | Error err -> Logger.log_error ~context:(Printf.sprintf "copy asset %s" f) err)
  in
  List.iter copy_asset non_typ
;;

let clean_stale_html_and_legacy ~html_dir ~project_dir keep_html =
  if Sys.file_exists html_dir && Sys.is_directory html_dir
  then (
    let entries = Sys.readdir html_dir in
    let clean_entry f =
      if String.ends_with ~suffix:".html" f
         && not (List.exists (String.equal f) keep_html)
      then (
        Logger.info "  [-] Removing stale HTML: %s" f;
        let to_remove = Filename.concat html_dir f in
        match Fs.rm_rf to_remove with
        | Ok () -> ()
        | Error err ->
          Logger.log_error ~context:(Printf.sprintf "remove stale html %s" to_remove) err)
    in
    Array.iter clean_entry entries);
  if Sys.file_exists project_dir && Sys.is_directory project_dir
  then (
    let entries = Sys.readdir project_dir in
    let clean_root e =
      if String.ends_with ~suffix:".html" e || String.ends_with ~suffix:".pdf" e
      then (
        Logger.info "  [-] Removing stray file from project root: %s" e;
        let path = Filename.concat project_dir e in
        match Fs.rm_rf path with
        | Ok () -> ()
        | Error err ->
          Logger.log_error ~context:(Printf.sprintf "remove root file %s" path) err)
    in
    Array.iter clean_root entries)
;;

let invalidate_cached_pdfs cached_pdf_dir =
  if Sys.file_exists cached_pdf_dir && Sys.is_directory cached_pdf_dir
  then (
    let files =
      Sys.readdir cached_pdf_dir
      |> Array.to_list
      |> List.map (Filename.concat cached_pdf_dir)
    in
    let remove_cached p =
      match Fs.rm_rf p with
      | Ok () -> ()
      | Error err ->
        Logger.log_error ~context:(Printf.sprintf "invalidate cached pdf %s" p) err
    in
    List.iter remove_cached files)
;;

let build_font_argument () =
  let cwd = Sys.getcwd () in
  let home = Sys.getenv_opt "HOME" |> Option.value ~default:"" in
  let font_dirs =
    [ Filename.concat cwd "site/assets/fonts"
    ; Filename.concat home "Library/Fonts"
    ; "/System/Library/Fonts/Supplemental"
    ; Filename.concat home ".local/share/fonts"
    ; "/usr/share/fonts"
    ; "/usr/local/share/fonts"
    ]
    |> List.filter (fun dir -> (not (String.equal dir "")) && Sys.file_exists dir)
  in
  match font_dirs with
  | [] -> ""
  | dirs ->
    let render_flag dir = Printf.sprintf "--font-path %s" (Filename.quote dir) in
    (dirs |> List.map render_flag |> String.concat " ") ^ " "
;;

let fetch_and_compile_repo_blogposts config state_ref force_rebuild (project : project) =
  let owner, repo =
    parse_github_repo
      ~repo_url:project.repo_url
      ~default_owner:Config.github_user
      ~fallback_repo:project.name
  in
  Logger.info "[%s] Checking repository: %s/%s ..." project.name owner repo;
  let remote_sha_opt =
    match get_remote_blog_sha ~owner ~repo with
    | Ok sha -> sha
    | Error err ->
      Logger.log_error
        ~context:(Printf.sprintf "get_remote_blog_sha for %s" project.name)
        err;
      None
  in
  let local_sha = List.assoc_opt project.name !state_ref in
  let needs_rebuild =
    force_rebuild
    ||
    match remote_sha_opt, local_sha with
    | Some r_sha, Some l_sha -> not (String.equal r_sha l_sha)
    | Some _, None -> true
    | None, _ -> false
  in
  let project_dir = Filename.concat (Config.get_projects_dir config) project.name in
  let html_dir = Filename.concat project_dir "html" in
  let pdfs_dir = Filename.concat project_dir "pdfs" in
  let cached_pdf_dir = Filename.concat html_dir "cached_pdf" in
  let* () = Fs.mkdir_p project_dir in
  let* () = Fs.mkdir_p html_dir in
  let* () = Fs.mkdir_p pdfs_dir in
  let* () = Fs.mkdir_p cached_pdf_dir in
  if not needs_rebuild
  then (
    Logger.info
      "  [SKIP] Up-to-date (SHA: %s)"
      (Option.value ~default:"unknown" local_sha);
    let* () = Page_gen.generate_project_page config project in
    Ok false)
  else (
    Logger.info "  [FETCH] Downloading file manifest from GitHub API...";
    let tree_url =
      Printf.sprintf "https://api.github.com/repos/%s/%s/contents/blog" owner repo
    in
    let* tree_json_str = Net.http_get tree_url in
    let* tree_json =
      try Ok (Yojson.Safe.from_string tree_json_str) with
      | exn ->
        Error
          (Error.json_parse_error
             ~context:(Printf.sprintf "contents for %s/%s" owner repo)
             ~raw:tree_json_str
             (Printexc.to_string exn))
    in
    match tree_json with
    | `List items ->
      let files =
        List.filter_map
          (fun item ->
            match item with
            | `Assoc fields ->
              (match
                 ( List.assoc_opt "type" fields
                 , List.assoc_opt "name" fields
                 , List.assoc_opt "download_url" fields )
               with
               | Some (`String "file"), Some (`String n), Some (`String u) -> Some (n, u)
               | _ -> None)
            | _ -> None)
          items
      in
      (match files with
       | [] ->
         Logger.info "  [INFO] No files found in %s/%s/blog/" owner repo;
         Ok false
       | _ ->
         let temp_root = Filename.concat "_fetch_tmp" project.name in
         let temp_blog = Filename.concat temp_root "blog" in
         let* () = Fs.mkdir_p temp_blog in
         let cwd = Sys.getcwd () in
         let template_source =
           Filename.concat (Filename.concat cwd "templates") "template.typ"
         in
         let temp_template = Filename.concat temp_root "template.typ" in
         if not (Sys.file_exists temp_template)
         then (
           match Fs.symlink_force ~src:template_source ~dest:temp_template with
           | Ok () -> ()
           | Error err -> Logger.log_error ~context:"symlink template.typ" err);
         let* () = download_repo_blog_files ~temp_blog files in
         let font_arg = build_font_argument () in
         let typ_files =
           List.filter (fun (f, _) -> String.ends_with ~suffix:".typ" f) files
         in
         let* generated_html_files =
           compile_typ_posts ~temp_blog ~temp_root ~html_dir ~project font_arg typ_files
         in
         copy_companion_assets ~temp_blog ~html_dir files;
         let keep_html = "index.html" :: generated_html_files in
         clean_stale_html_and_legacy ~html_dir ~project_dir keep_html;
         (match remote_sha_opt with
          | Some sha ->
            state_ref := (project.name, sha) :: List.remove_assoc project.name !state_ref;
            invalidate_cached_pdfs cached_pdf_dir
          | None -> ());
         Ok true)
    | `Assoc fields ->
      (match List.assoc_opt "message" fields with
       | Some (`String msg) when String.equal msg "Not Found" ->
         Logger.info
           "  [INFO] Repo '%s/%s' does not have a 'blog/' directory yet on GitHub."
           owner
           repo;
         Ok false
       | Some (`String msg) ->
         Error (Error.github_api_failed ~endpoint:(Printf.sprintf "%s/%s" owner repo) msg)
       | Some _ | None ->
         Error
           (Error.github_api_failed
              ~endpoint:(Printf.sprintf "%s/%s" owner repo)
              "Unknown response format"))
    | `Null | `Bool _ | `Int _ | `Intlit _ | `Float _ | `String _ ->
      Error
        (Error.github_api_failed
           ~endpoint:(Printf.sprintf "%s/%s" owner repo)
           "Expected JSON array or object"))
;;

let run_sync (config : Config.t) state_ref ~force_rebuild =
  Logger.info "=== BuzzYbis Project & Blog Sync ===";
  Logger.info "Reading configuration from %s..." Config.config_file;
  match config.projects with
  | [] ->
    Logger.warn
      "No projects found in %s. Please add your repositories there."
      Config.config_file
  | _ ->
    (match ensure_clean_repo_site config with
     | Ok () -> ()
     | Error err -> Logger.log_error ~context:"ensure_clean_repo_site" err);
    cleanup_unconfigured_projects config;
    List.iter (clean_expired_cached_pdfs config) config.projects;
    let any_rebuilt = ref false in
    List.iter
      (fun project ->
        match fetch_and_compile_repo_blogposts config state_ref force_rebuild project with
        | Ok rebuilt ->
          if rebuilt then any_rebuilt := true;
          (match Page_gen.generate_project_page config project with
           | Ok () -> ()
           | Error err ->
             Logger.log_error
               ~context:(Printf.sprintf "generate_project_page for %s" project.name)
               err)
        | Error err ->
          Logger.log_error
            ~context:(Printf.sprintf "fetch_and_compile for %s" project.name)
            err)
      config.projects;
    (match Config.save_fetch_state config !state_ref with
     | Ok () -> ()
     | Error err -> Logger.log_error ~context:"save_fetch_state" err);
    (match Page_gen.generate_projects_directory config config.projects with
     | Ok () -> ()
     | Error err -> Logger.log_error ~context:"generate_projects_directory" err);
    (match Page_gen.generate_home_page config config.projects with
     | Ok () -> ()
     | Error err -> Logger.log_error ~context:"generate_home_page" err);
    if !any_rebuilt
    then (
      Logger.info "Triggering Soupault build to incorporate new blogposts...";
      match Net.run_cmd "make build" with
      | Ok (Unix.WEXITED 0, _) -> Logger.info "[✔] Full build completed successfully."
      | Ok (Unix.WEXITED code, out) ->
        Logger.log_error
          ~context:"Soupault build"
          (Error.Typst
             (Error.Typst_compile_failed
                { src = "soupault"; exit_code = code; output = out }))
      | Ok ((Unix.WSIGNALED _ | Unix.WSTOPPED _), out) ->
        Logger.log_error
          ~context:"Soupault build"
          (Error.Typst
             (Error.Typst_compile_failed { src = "soupault"; exit_code = 1; output = out }))
      | Error err -> Logger.log_error ~context:"Soupault build" err)
    else Logger.info "[✔] Everything is up-to-date. No rebuild needed."
;;

let main () =
  Logger.init ();
  let args = Array.to_list Sys.argv |> List.tl in
  let is_force = List.mem "--force" args || List.mem "-f" args in
  let is_watch = List.mem "--watch" args || List.mem "-w" args in
  let is_pages_only = List.mem "--pages-only" args in
  let poll_arg =
    let rec find_poll = function
      | "--poll" :: n :: _ ->
        (try Some (int_of_string n) with
         | Failure _ -> None)
      | _ :: rest -> find_poll rest
      | [] -> None
    in
    find_poll args
  in
  let config =
    match Config.load_projects_toml Config.config_file with
    | Ok cfg -> cfg
    | Error err ->
      Logger.log_error ~context:"Config.load_projects_toml" err;
      exit 1
  in
  if is_pages_only
  then (
    (match ensure_clean_repo_site config with
     | Ok () -> ()
     | Error err -> Logger.log_error ~context:"ensure_clean_repo_site" err);
    List.iter (clean_expired_cached_pdfs config) config.projects;
    List.iter
      (fun p ->
        match Page_gen.generate_project_page config p with
        | Ok () -> ()
        | Error err ->
          Logger.log_error
            ~context:(Printf.sprintf "generate_project_page for %s" p.name)
            err)
      config.projects;
    (match Page_gen.generate_projects_directory config config.projects with
     | Ok () -> ()
     | Error err -> Logger.log_error ~context:"generate_projects_directory" err);
    (match Page_gen.generate_home_page config config.projects with
     | Ok () -> ()
     | Error err -> Logger.log_error ~context:"generate_home_page" err);
    exit 0);
  let interval =
    match poll_arg with
    | Some n -> n
    | None -> config.poll_interval
  in
  let state_ref = ref (Config.load_fetch_state config) in
  if is_watch || Option.is_some poll_arg
  then (
    Logger.info "BuzzYbis Watch Daemon started (checking every %d seconds)." interval;
    Logger.info "Press Ctrl+C to stop.";
    Sys.set_signal
      Sys.sigint
      (Sys.Signal_handle
         (fun _ ->
           Logger.info "Stopping watch daemon.";
           exit 0));
    while true do
      run_sync config state_ref ~force_rebuild:is_force;
      Unix.sleep interval
    done)
  else run_sync config state_ref ~force_rebuild:is_force
;;
