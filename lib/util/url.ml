(* URL parsing and path validation utilities *)

let is_abs_or_remote url =
  let uri = Uri.of_string url in
  match Uri.scheme uri with
  | Some _ -> true
  | None -> String.starts_with ~prefix:"/" (Uri.path uri)
;;

let default_title_of_basename basename =
  if String.ends_with ~suffix:".pdf" (String.lowercase_ascii basename)
  then (
    let base = Filename.remove_extension basename in
    Printf.sprintf "%s (PDF)" (String.capitalize_ascii base))
  else basename
;;
