(* HTML parsing, sanitization, and text extraction utilities *)

let escape_html s =
  let buf = Buffer.create (String.length s) in
  let escape_char = function
    | '&' -> Buffer.add_string buf "&amp;"
    | '<' -> Buffer.add_string buf "&lt;"
    | '>' -> Buffer.add_string buf "&gt;"
    | '"' -> Buffer.add_string buf "&quot;"
    | '\'' -> Buffer.add_string buf "&#39;"
    | c -> Buffer.add_char buf c
  in
  String.iter escape_char s;
  Buffer.contents buf
;;

let has_substring ~sub s =
  let len_s = String.length s in
  let len_sub = String.length sub in
  if Int.equal len_sub 0
  then true
  else if len_sub > len_s
  then false
  else (
    let sub_lower = String.lowercase_ascii sub in
    let s_lower = String.lowercase_ascii s in
    let rec check i =
      if i + len_sub > len_s
      then false
      else if String.equal (String.sub s_lower i len_sub) sub_lower
      then true
      else check (i + 1)
    in
    check 0)
;;

let string_contains = has_substring

let add_external_link_targets html =
  let soup = Soup.parse html in
  let add_target a =
    match Soup.attribute "href" a with
    | Some h
      when String.starts_with ~prefix:"http://" h
           || String.starts_with ~prefix:"https://" h ->
      Soup.set_attribute "target" "_blank" a;
      Soup.set_attribute "rel" "noopener noreferrer" a
    | Some _ | None -> ()
  in
  Soup.iter add_target (Soup.select "a" soup);
  Soup.to_string soup
;;

let clean_html_text raw =
  let soup = Soup.parse raw in
  Soup.texts soup |> String.concat "" |> String.trim
;;

let clean_subtitle raw = clean_html_text raw

let clean_authors raw =
  let soup = Soup.parse raw in
  let links = Soup.select "a" soup |> Soup.to_list in
  match links with
  | [] ->
    let text = Soup.texts soup |> String.concat "" |> String.trim in
    let stripped =
      if String.starts_with ~prefix:"By " text
      then String.sub text 3 (String.length text - 3) |> String.trim
      else if String.starts_with ~prefix:"by " text
      then String.sub text 3 (String.length text - 3) |> String.trim
      else text
    in
    escape_html stripped
  | _ ->
    let format_link a =
      let name = Soup.leaf_text a |> Option.value ~default:"" |> String.trim in
      let stripped =
        if String.starts_with ~prefix:"By " name
        then String.sub name 3 (String.length name - 3) |> String.trim
        else if String.starts_with ~prefix:"by " name
        then String.sub name 3 (String.length name - 3) |> String.trim
        else name
      in
      let href = Soup.attribute "href" a |> Option.value ~default:"" in
      if not (String.equal href "")
      then
        Printf.sprintf
          "<a href=\"%s\" target=\"_blank\" rel=\"noopener noreferrer\">%s</a>"
          (escape_html href)
          (escape_html stripped)
      else escape_html stripped
    in
    links |> List.map format_link |> String.concat ", "
;;

let clean_tag_name t =
  let trimmed = String.trim t in
  if String.starts_with ~prefix:"#" trimmed
  then String.sub trimmed 1 (String.length trimmed - 1) |> String.trim
  else trimmed
;;

let extract_date_from_text text =
  let len = String.length text in
  let is_digit c = Char.code c >= Char.code '0' && Char.code c <= Char.code '9' in
  let rec scan i =
    if i + 10 > len
    then None
    else if is_digit text.[i]
            && is_digit text.[i + 1]
            && is_digit text.[i + 2]
            && is_digit text.[i + 3]
            && Char.equal text.[i + 4] '-'
            && is_digit text.[i + 5]
            && is_digit text.[i + 6]
            && Char.equal text.[i + 7] '-'
            && is_digit text.[i + 8]
            && is_digit text.[i + 9]
    then Some (String.sub text i 10)
    else scan (i + 1)
  in
  scan 0
;;
