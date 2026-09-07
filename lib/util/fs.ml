(* Filesystem utilities with scoped channel resource management and atomic writes *)

open Syntax

let with_in_channel ~path f =
  try In_channel.with_open_text path f with
  | exn -> Error (Error.of_exn ~op:Error.Read ~path exn)
;;

let with_out_channel ~path f =
  try Out_channel.with_open_text path f with
  | exn -> Error (Error.of_exn ~op:Error.Write ~path exn)
;;

let atomic_write_file ~path ~content =
  let tmp = Printf.sprintf "%s.tmp.%d" path (Unix.getpid ()) in
  try
    Out_channel.with_open_bin tmp (fun oc -> Out_channel.output_string oc content);
    Sys.rename tmp path;
    Ok ()
  with
  | exn ->
    (try Sys.remove tmp with
     | Sys_error _ | Unix.Unix_error _ -> ());
    Error (Error.of_exn ~op:Error.Write ~path exn)
;;

let rec mkdir_p dir =
  if not (Sys.file_exists dir)
  then (
    let parent = Filename.dirname dir in
    let* () = if not (String.equal parent dir) then mkdir_p parent else Ok () in
    try
      Unix.mkdir dir 0o755;
      Ok ()
    with
    | Unix.Unix_error (Unix.EEXIST, _, _) -> Ok ()
    | exn -> Error (Error.of_exn ~op:Error.Mkdir ~path:dir exn))
  else Ok ()
;;

let rec rm_rf path =
  if Sys.file_exists path
  then (
    let is_symlink =
      try (Unix.lstat path).Unix.st_kind = Unix.S_LNK with
      | Unix.Unix_error _ -> false
    in
    if Sys.is_directory path && not is_symlink
    then (
      let entries =
        try Sys.readdir path with
        | Sys_error _ | Unix.Unix_error _ -> [||]
      in
      let rec remove_entries idx =
        if idx >= Array.length entries
        then (
          try
            Unix.rmdir path;
            Ok ()
          with
          | exn -> Error (Error.of_exn ~op:Error.Rmdir ~path exn))
        else (
          let child = Filename.concat path entries.(idx) in
          let* () = rm_rf child in
          remove_entries (idx + 1))
      in
      remove_entries 0)
    else (
      try
        Sys.remove path;
        Ok ()
      with
      | exn -> Error (Error.of_exn ~op:Error.Remove ~path exn)))
  else Ok ()
;;

let symlink_force ~src ~dest =
  if Sys.file_exists dest
  then (
    try Sys.remove dest with
    | Sys_error _ | Unix.Unix_error _ -> ());
  try
    Unix.symlink src dest;
    Ok ()
  with
  | exn ->
    Error
      (Error.Fs (Error.Fs_symlink_failed { src; dest; details = Printexc.to_string exn }))
;;

let rec cp_r ~src ~dest =
  if Sys.is_directory src
  then
    let* () = mkdir_p dest in
    let entries = Sys.readdir src in
    let rec copy_entries idx =
      if idx >= Array.length entries
      then Ok ()
      else (
        let entry = entries.(idx) in
        let* () =
          cp_r ~src:(Filename.concat src entry) ~dest:(Filename.concat dest entry)
        in
        copy_entries (idx + 1))
    in
    copy_entries 0
  else (
    try
      In_channel.with_open_bin src (fun ic ->
        let data = In_channel.input_all ic in
        atomic_write_file ~path:dest ~content:data)
    with
    | exn -> Error (Error.of_exn ~op:Error.Read ~path:src exn))
;;
