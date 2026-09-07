(* Configuration types and TOML parser for projects.toml *)

module Fs = Util.Fs
module Url = Util.Url

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

type t =
  { mutable projects_dir : string
  ; mutable poll_interval : int
  ; mutable projects : project list
  }

type app_config = t

let github_user = "BuzzYbis"
let config_file = "projects.toml"

let parse_string_list str =
  let trimmed = String.trim str in
  if String.starts_with ~prefix:"[" trimmed && String.ends_with ~suffix:"]" trimmed
  then (
    let inner = String.sub trimmed 1 (String.length trimmed - 2) in
    String.split_on_char ',' inner
    |> List.map String.trim
    |> List.filter (fun s -> not (String.equal s ""))
    |> List.map (fun s ->
      if String.starts_with ~prefix:"\"" s && String.ends_with ~suffix:"\"" s
      then String.sub s 1 (String.length s - 2)
      else s))
  else []
;;

let parse_string_val raw =
  let trimmed = String.trim raw in
  if String.starts_with ~prefix:"\"" trimmed && String.ends_with ~suffix:"\"" trimmed
  then String.sub trimmed 1 (String.length trimmed - 2)
  else trimmed
;;

let expand_path path =
  let p = String.trim path in
  let raw =
    if String.starts_with ~prefix:"~/" p
    then (
      let home = Sys.getenv_opt "HOME" |> Option.value ~default:"" in
      Filename.concat home (String.sub p 2 (String.length p - 2)))
    else if Filename.is_relative p
    then Filename.concat (Sys.getcwd ()) p
    else p
  in
  ignore (Fs.mkdir_p raw : (unit, Error.t) result);
  try Unix.realpath raw with
  | Unix.Unix_error _ -> raw
;;

let get_projects_dir (config : t) =
  let p =
    if not (String.equal config.projects_dir "")
    then config.projects_dir
    else "../buzzybis_projects"
  in
  expand_path p
;;

let get_projects_dir_standalone () =
  let default_dir = "../buzzybis_projects" in
  let dir =
    if Sys.file_exists config_file
    then (
      try
        In_channel.with_open_text config_file (fun ic ->
          let d = ref default_dir in
          (try
             while true do
               let line = String.trim (input_line ic) in
               if (not (String.equal line "")) && not (Char.equal line.[0] '#')
               then
                 if String.starts_with ~prefix:"projects_dir" line
                 then (
                   match String.split_on_char '=' line with
                   | _ :: v :: _ -> d := parse_string_val v
                   | _ -> ())
             done
           with
           | End_of_file -> ());
          !d)
      with
      | Sys_error _ | Unix.Unix_error _ -> default_dir)
    else default_dir
  in
  expand_path dir
;;

let load_projects_toml filepath =
  let config = { projects_dir = ""; poll_interval = 15; projects = [] } in
  if not (Sys.file_exists filepath)
  then Error (Error.config_missing filepath)
  else (
    let current_section = ref "" in
    let current_proj = ref None in
    try
      In_channel.with_open_text filepath (fun ic ->
        try
          while true do
            let line = String.trim (input_line ic) in
            if (not (String.equal line "")) && not (Char.equal line.[0] '#')
            then
              if String.starts_with ~prefix:"[" line && String.ends_with ~suffix:"]" line
              then (
                let sec_name =
                  String.sub line 1 (String.length line - 2) |> String.trim
                in
                if String.equal sec_name "settings" || String.equal sec_name "site"
                then (
                  current_section := "settings";
                  current_proj := None)
                else (
                  current_section := "project";
                  let project =
                    { name = sec_name
                    ; title = sec_name
                    ; description = ""
                    ; collaborators = []
                    ; repo_url =
                        Printf.sprintf "https://github.com/%s/%s" github_user sec_name
                    ; tags = []
                    ; downloads = []
                    }
                  in
                  config.projects <- project :: config.projects;
                  current_proj := Some project))
              else (
                match !current_section with
                | "settings" | "site" ->
                  (match String.split_on_char '=' line with
                   | key :: rest ->
                     let key = String.trim key in
                     let raw_val = String.concat "=" rest |> String.trim in
                     (match key with
                      | "projects_dir" -> config.projects_dir <- parse_string_val raw_val
                      | "poll_interval" ->
                        config.poll_interval
                        <- (try int_of_string (parse_string_val raw_val) with
                            | Failure _ -> 15)
                      | _ -> ())
                   | [] -> ())
                | "project" ->
                  (match !current_proj with
                   | Some project ->
                     (match String.split_on_char '=' line with
                      | key :: rest ->
                        let key = String.trim key in
                        let raw_val = String.concat "=" rest |> String.trim in
                        let value =
                          if String.starts_with ~prefix:"[" raw_val
                             && not (String.ends_with ~suffix:"]" raw_val)
                          then (
                            let buf = Buffer.create 256 in
                            Buffer.add_string buf raw_val;
                            let found_end = ref false in
                            (try
                               while not !found_end do
                                 let next_line = String.trim (input_line ic) in
                                 if (not (String.equal next_line ""))
                                    && not (Char.equal next_line.[0] '#')
                                 then (
                                   Buffer.add_char buf ' ';
                                   Buffer.add_string buf next_line;
                                   if String.ends_with ~suffix:"]" next_line
                                   then found_end := true)
                               done
                             with
                             | End_of_file -> ());
                            Buffer.contents buf)
                          else raw_val
                        in
                        (match key with
                         | "title" -> project.title <- parse_string_val value
                         | "description" -> project.description <- parse_string_val value
                         | "repo" | "repo_url" ->
                           project.repo_url <- parse_string_val value
                         | "collaborators" ->
                           project.collaborators <- parse_string_list value
                         | "tags" -> project.tags <- parse_string_list value
                         | "downloads" ->
                           let raw_list = parse_string_list value in
                           let items =
                             raw_list
                             |> List.map (fun item ->
                               let trimmed = String.trim item in
                               if String.contains trimmed '='
                               then (
                                 match String.split_on_char '=' trimmed with
                                 | title_part :: url_parts ->
                                   let t = String.trim title_part in
                                   let u = String.trim (String.concat "=" url_parts) in
                                   let final_url =
                                     if Url.is_abs_or_remote u
                                     then u
                                     else Printf.sprintf "/project/%s/%s" project.name u
                                   in
                                   let label =
                                     if String.equal t "" then "Download" else t
                                   in
                                   { label; url = final_url }
                                 | [] -> { label = "Download"; url = "" })
                               else if String.contains trimmed ':'
                               then (
                                 match String.split_on_char ':' trimmed with
                                 | title_part :: url_parts ->
                                   let t = String.trim title_part in
                                   let u = String.trim (String.concat ":" url_parts) in
                                   let final_url =
                                     if Url.is_abs_or_remote u
                                     then u
                                     else Printf.sprintf "/project/%s/%s" project.name u
                                   in
                                   let label =
                                     if String.equal t "" then "Download" else t
                                   in
                                   { label; url = final_url }
                                 | [] -> { label = "Download"; url = "" })
                               else (
                                 let final_url =
                                   if Url.is_abs_or_remote trimmed
                                   then trimmed
                                   else
                                     Printf.sprintf "/project/%s/%s" project.name trimmed
                                 in
                                 let default_label =
                                   Url.default_title_of_basename
                                     (Filename.basename trimmed)
                                 in
                                 { label = default_label; url = final_url }))
                           in
                           project.downloads <- project.downloads @ items
                         | "download" ->
                           let u = parse_string_val value in
                           let final_url =
                             if Url.is_abs_or_remote u
                             then u
                             else Printf.sprintf "/project/%s/%s" project.name u
                           in
                           let default_label =
                             Url.default_title_of_basename (Filename.basename u)
                           in
                           project.downloads
                           <- project.downloads
                              @ [ { label = default_label; url = final_url } ]
                         | "download_title" | "download_label" ->
                           let t = parse_string_val value in
                           (match List.rev project.downloads with
                            | last :: rest ->
                              project.downloads
                              <- List.rev ({ last with label = t } :: rest)
                            | [] -> ())
                         | _ -> ())
                      | [] -> ())
                   | None -> ())
                | _ -> ())
          done
        with
        | End_of_file -> ());
      config.projects <- List.rev config.projects;
      Ok config
    with
    | exn -> Error (Error.config_parse_error ~file:filepath (Printexc.to_string exn)))
;;

let get_state_file (config : t) =
  let dir = get_projects_dir config in
  Filename.concat dir "fetch_state.json"
;;

let load_fetch_state (config : t) =
  let state_file = get_state_file config in
  if Sys.file_exists state_file
  then (
    try
      let json = Yojson.Safe.from_file state_file in
      match json with
      | `Assoc items ->
        List.filter_map
          (fun (k, v) ->
            match v with
            | `String sha -> Some (k, sha)
            | _ -> None)
          items
      | _ -> []
    with
    | Sys_error _ | Yojson.Json_error _ -> [])
  else []
;;

let save_fetch_state (config : t) state =
  let state_file = get_state_file config in
  let json = `Assoc (List.map (fun (k, sha) -> k, `String sha) state) in
  let tmp_file = Printf.sprintf "%s.tmp.%d" state_file (Unix.getpid ()) in
  try
    Yojson.Safe.to_file tmp_file json;
    Sys.rename tmp_file state_file;
    Ok ()
  with
  | exn ->
    (try Sys.remove tmp_file with
     | Sys_error _ | Unix.Unix_error _ -> ());
    Error (Error.json_write_error ~path:state_file (Printexc.to_string exn))
;;
