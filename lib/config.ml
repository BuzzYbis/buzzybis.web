(* Configuration types and a minimal TOML reader for projects.toml. *)

open Util.Syntax
module Fs = Util.Fs
module Url = Util.Url

type download_item =
  { label : string
  ; url : string
  }

type project =
  { name : string
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

type project_paths =
  { project_dir : string
  ; html_dir : string
  ; pdfs_dir : string
  ; cached_pdf_dir : string
  }

let github_user = "BuzzYbis"
let config_file = "projects.toml"
let default_projects_dir = "../buzzybis_projects"
let default_poll_interval = 300
let fetch_tmp_dir = "_fetch_tmp"

let empty =
  { projects_dir = default_projects_dir
  ; poll_interval = default_poll_interval
  ; projects = []
  }
;;

(* Paths *)

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
  try Unix.realpath raw with
  | Unix.Unix_error _ -> raw
;;

let projects_dir config =
  expand_path
    (if String.equal config.projects_dir ""
     then default_projects_dir
     else config.projects_dir)
;;

let project_paths config project =
  let project_dir = Filename.concat (projects_dir config) project.name in
  let html_dir = Filename.concat project_dir "html" in
  { project_dir
  ; html_dir
  ; pdfs_dir = Filename.concat project_dir "pdfs"
  ; cached_pdf_dir = Filename.concat html_dir "cached_pdf"
  }
;;

let project_url_path project = Printf.sprintf "/project/%s" project.name

(* Value parsing *)

let strip_quotes s =
  let trimmed = String.trim s in
  let len = String.length trimmed in
  if
    len >= 2
    && String.starts_with ~prefix:"\"" trimmed
    && String.ends_with ~suffix:"\"" trimmed
  then String.sub trimmed 1 (len - 2)
  else trimmed
;;

let parse_string_val = strip_quotes

let parse_string_list str =
  let trimmed = String.trim str in
  if
    String.length trimmed >= 2
    && String.starts_with ~prefix:"[" trimmed
    && String.ends_with ~suffix:"]" trimmed
  then
    String.sub trimmed 1 (String.length trimmed - 2)
    |> String.split_on_char ','
    |> List.map String.trim
    |> List.filter (fun s -> not (String.equal s ""))
    |> List.map strip_quotes
  else []
;;

(* Downloads *)

let resolve_download_url project url =
  if Url.is_abs_or_remote url
  then url
  else Printf.sprintf "%s/%s" (project_url_path project) url
;;

let plain_download project url =
  { label = Url.default_title_of_basename (Filename.basename url)
  ; url = resolve_download_url project url
  }
;;

(* A download list entry is either "Label = target", "Label: target", or a bare target. *)
let download_item project raw =
  let item = String.trim raw in
  let split_at sep =
    Option.map
      (fun i ->
         ( String.trim (String.sub item 0 i)
         , String.trim (String.sub item (i + 1) (String.length item - i - 1)) ))
      (String.index_opt item sep)
  in
  let labelled (label, target) =
    { label = (if String.equal label "" then "Download" else label)
    ; url = resolve_download_url project target
    }
  in
  (* "https://host/x" is a bare URL, not a "https" label followed by "//host/x". *)
  let is_bare_url =
    match split_at ':' with
    | Some (_, rest) -> String.starts_with ~prefix:"//" rest
    | None -> false
  in
  match split_at '=' with
  | Some pair -> labelled pair
  | None when is_bare_url -> plain_download project item
  | None ->
    (match split_at ':' with
     | Some pair -> labelled pair
     | None -> plain_download project item)
;;

let relabel_last_download project label =
  match List.rev project.downloads with
  | last :: rest -> { project with downloads = List.rev ({ last with label } :: rest) }
  | [] -> project
;;

(* Line-oriented TOML subset *)

type line =
  | Blank
  | Section of string
  | Key_value of string * string

let is_blank_or_comment line = String.equal line "" || Char.equal line.[0] '#'

let split_key_value line =
  Option.map
    (fun i ->
       ( String.trim (String.sub line 0 i)
       , String.trim (String.sub line (i + 1) (String.length line - i - 1)) ))
    (String.index_opt line '=')
;;

let classify line =
  if is_blank_or_comment line
  then Blank
  else if String.starts_with ~prefix:"[" line && String.ends_with ~suffix:"]" line
  then Section (String.trim (String.sub line 1 (String.length line - 2)))
  else (
    match split_key_value line with
    | Some (key, value) -> Key_value (key, value)
    | None -> Blank)
;;

(* Inline arrays may span several lines; fold the continuation lines into one. *)
let join_multiline_arrays lines =
  let opens_array line =
    match split_key_value line with
    | Some (_, value) ->
      String.starts_with ~prefix:"[" value && not (String.ends_with ~suffix:"]" value)
    | None -> false
  in
  let rec absorb buf = function
    | [] -> buf, []
    | line :: rest when is_blank_or_comment line -> absorb buf rest
    | line :: rest ->
      let buf = buf ^ " " ^ line in
      if String.ends_with ~suffix:"]" line then buf, rest else absorb buf rest
  in
  let rec go acc = function
    | [] -> List.rev acc
    | line :: rest when opens_array line ->
      let joined, rest = absorb line rest in
      go (joined :: acc) rest
    | line :: rest -> go (line :: acc) rest
  in
  go [] lines
;;

type section =
  | Preamble
  | Settings
  | Project

type state =
  { s_projects_dir : string
  ; s_poll_interval : int
  ; s_projects : project list (* reversed; head is the section being parsed *)
  ; s_section : section
  }

let new_project name =
  { name
  ; title = name
  ; description = ""
  ; collaborators = []
  ; repo_url = Printf.sprintf "https://github.com/%s/%s" github_user name
  ; tags = []
  ; downloads = []
  }
;;

let apply_setting state key value =
  match key with
  | "projects_dir" -> { state with s_projects_dir = parse_string_val value }
  | "poll_interval" ->
    { state with
      s_poll_interval =
        int_of_string_opt (parse_string_val value)
        |> Option.value ~default:default_poll_interval
    }
  | _ -> state
;;

let apply_project_key project key value =
  match key with
  | "title" -> { project with title = parse_string_val value }
  | "description" -> { project with description = parse_string_val value }
  | "repo" | "repo_url" -> { project with repo_url = parse_string_val value }
  | "collaborators" -> { project with collaborators = parse_string_list value }
  | "tags" -> { project with tags = parse_string_list value }
  | "downloads" ->
    let items = parse_string_list value |> List.map (download_item project) in
    { project with downloads = project.downloads @ items }
  | "download" ->
    { project with
      downloads = project.downloads @ [ plain_download project (parse_string_val value) ]
    }
  | "download_title" | "download_label" ->
    relabel_last_download project (parse_string_val value)
  | _ -> project
;;

let step state = function
  | Blank -> Ok state
  | Section ("settings" | "site") -> Ok { state with s_section = Settings }
  | Section name ->
    if Fs.is_safe_name name
    then
      Ok
        { state with
          s_section = Project
        ; s_projects = new_project name :: state.s_projects
        }
    else
      Error
        (Error.config_invalid_val
           ~field:"section"
           ~raw:name
           "project names may only contain ASCII letters, digits, '-', '_' and '.'")
  | Key_value (key, value) ->
    (match state.s_section, state.s_projects with
     | Settings, _ -> Ok (apply_setting state key value)
     | Project, current :: rest ->
       Ok { state with s_projects = apply_project_key current key value :: rest }
     | Project, [] | Preamble, _ -> Ok state)
;;

let parse content =
  let initial =
    { s_projects_dir = ""
    ; s_poll_interval = default_poll_interval
    ; s_projects = []
    ; s_section = Preamble
    }
  in
  let lines =
    String.split_on_char '\n' content
    |> List.map String.trim
    |> join_multiline_arrays
    |> List.map classify
  in
  let rec fold state = function
    | [] -> Ok state
    | line :: rest ->
      let* state = step state line in
      fold state rest
  in
  let+ state = fold initial lines in
  { projects_dir = state.s_projects_dir
  ; poll_interval = state.s_poll_interval
  ; projects = List.rev state.s_projects
  }
;;

let load path =
  if not (Sys.file_exists path)
  then Error (Error.config_missing path)
  else (
    match In_channel.with_open_text path In_channel.input_all with
    | content -> parse content
    | exception (Sys_error _ as exn) -> Error (Error.of_exn ~op:Error.Read ~path exn))
;;

let find_project config name =
  List.find_opt (fun project -> String.equal project.name name) config.projects
;;

(* Fetch state *)

let state_file config = Filename.concat (projects_dir config) "fetch_state.json"

let load_fetch_state config =
  Fs.read_json_assoc (state_file config)
  |> List.filter_map (fun (name, value) ->
    match value with
    | `String sha -> Some (name, sha)
    | _ -> None)
;;

let save_fetch_state config state =
  Fs.write_json
    ~path:(state_file config)
    (`Assoc (List.map (fun (name, sha) -> name, `String sha) state))
;;
