(* Filesystem utilities: safe names, atomic writes, recursive operations. *)

open Syntax

let is_safe_name name =
  let allowed = function
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' | '.' -> true
    | _ -> false
  in
  (not (String.equal name ""))
  && (not (String.starts_with ~prefix:"." name))
  && String.for_all allowed name
;;

let check_safe_name name =
  if is_safe_name name then Ok name else Error (Error.unsafe_name name)
;;

let remove_noerr path =
  try Sys.remove path with
  | Sys_error _ -> ()
;;

let kind path =
  try Some (Unix.lstat path).Unix.st_kind with
  | Unix.Unix_error _ -> None
;;

let is_regular_file path =
  try (Unix.stat path).Unix.st_kind = Unix.S_REG with
  | Unix.Unix_error _ -> false
;;

let is_directory path = Sys.file_exists path && Sys.is_directory path

let atomic_write_file ~path ~content =
  let tmp = Printf.sprintf "%s.tmp.%d" path (Unix.getpid ()) in
  match
    Out_channel.with_open_bin tmp (fun oc -> Out_channel.output_string oc content);
    Sys.rename tmp path
  with
  | () -> Ok ()
  | exception exn ->
    remove_noerr tmp;
    Error (Error.of_exn ~op:Error.Write ~path exn)
;;

let write_json ~path json = atomic_write_file ~path ~content:(Yojson.Safe.to_string json)

let read_json_assoc path =
  if not (Sys.file_exists path)
  then []
  else (
    match Yojson.Safe.from_file path with
    | `Assoc items -> items
    | _ -> []
    | exception (Sys_error _ | Yojson.Json_error _ | End_of_file) -> [])
;;

let rec mkdir_p dir =
  if Sys.file_exists dir
  then Ok ()
  else (
    let parent = Filename.dirname dir in
    let* () = if String.equal parent dir then Ok () else mkdir_p parent in
    match Unix.mkdir dir 0o755 with
    | () -> Ok ()
    | exception Unix.Unix_error (Unix.EEXIST, _, _) -> Ok ()
    | exception exn -> Error (Error.of_exn ~op:Error.Mkdir ~path:dir exn))
;;

let mkdir_all dirs = Result_list.iter mkdir_p dirs

let rec rm_rf path =
  match kind path with
  | None -> Ok ()
  | Some Unix.S_DIR ->
    let entries =
      try Array.to_list (Sys.readdir path) with
      | Sys_error _ -> []
    in
    let* () =
      Result_list.iter (fun entry -> rm_rf (Filename.concat path entry)) entries
    in
    (match Unix.rmdir path with
     | () -> Ok ()
     | exception exn -> Error (Error.of_exn ~op:Error.Rmdir ~path exn))
  | Some _ ->
    (match Sys.remove path with
     | () -> Ok ()
     | exception exn -> Error (Error.of_exn ~op:Error.Remove ~path exn))
;;

let symlink_force ~src ~dest =
  if Option.is_some (kind dest) then remove_noerr dest;
  match Unix.symlink src dest with
  | () -> Ok ()
  | exception exn ->
    let details =
      match exn with
      | Unix.Unix_error (err, _, _) -> Unix.error_message err
      | exn -> Printexc.to_string exn
    in
    Error (Error.Fs (Error.Fs_symlink_failed { src; dest; details }))
;;

let rec cp_r ~src ~dest =
  if Sys.is_directory src
  then
    let* () = mkdir_p dest in
    Sys.readdir src
    |> Array.to_list
    |> Result_list.iter (fun entry ->
      cp_r ~src:(Filename.concat src entry) ~dest:(Filename.concat dest entry))
  else (
    match In_channel.with_open_bin src In_channel.input_all with
    | content -> atomic_write_file ~path:dest ~content
    | exception exn -> Error (Error.of_exn ~op:Error.Read ~path:src exn))
;;

let list_dir path =
  if is_directory path
  then (
    try Array.to_list (Sys.readdir path) with
    | Sys_error _ -> [])
  else []
;;

let is_basename name =
  (not (String.equal name ""))
  && (not (String.equal name "."))
  && (not (String.equal name ".."))
  && (not (String.contains name '\000'))
  && String.equal (Filename.basename name) name
;;

let check_basename name =
  if is_basename name then Ok name else Error (Error.unsafe_name name)
;;
