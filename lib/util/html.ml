(* HTML escaping, parsing and text extraction. *)

let escape_html s =
  let buf = Buffer.create (String.length s) in
  String.iter
    (function
      | '&' -> Buffer.add_string buf "&amp;"
      | '<' -> Buffer.add_string buf "&lt;"
      | '>' -> Buffer.add_string buf "&gt;"
      | '"' -> Buffer.add_string buf "&quot;"
      | '\'' -> Buffer.add_string buf "&#39;"
      | c -> Buffer.add_char buf c)
    s;
  Buffer.contents buf
;;

let is_external_href href =
  String.starts_with ~prefix:"http://" href || String.starts_with ~prefix:"https://" href
;;

let set_external_link_targets soup =
  Soup.select "a" soup
  |> Soup.iter (fun a ->
    match Soup.attribute "href" a with
    | Some href when is_external_href href ->
      Soup.set_attribute "target" "_blank" a;
      Soup.set_attribute "rel" "noopener noreferrer" a
    | Some _ | None -> ())
;;

let text_content node = Soup.texts node |> String.concat "" |> String.trim

let strip_by_prefix s =
  if
    String.length s >= 3 && String.equal (String.lowercase_ascii (String.sub s 0 3)) "by "
  then String.trim (String.sub s 3 (String.length s - 3))
  else s
;;

let clean_authors raw =
  let soup = Soup.parse raw in
  match Soup.select "a" soup |> Soup.to_list with
  | [] -> escape_html (strip_by_prefix (text_content soup))
  | links ->
    let format_link a =
      let name =
        Soup.leaf_text a |> Option.value ~default:"" |> String.trim |> strip_by_prefix
      in
      match Soup.attribute "href" a with
      | Some href when not (String.equal href "") ->
        Printf.sprintf
          "<a href=\"%s\" target=\"_blank\" rel=\"noopener noreferrer\">%s</a>"
          (escape_html href)
          (escape_html name)
      | Some _ | None -> escape_html name
    in
    links |> List.map format_link |> String.concat ", "
;;

let clean_tag_name tag =
  let trimmed = String.trim tag in
  if String.starts_with ~prefix:"#" trimmed
  then String.trim (String.sub trimmed 1 (String.length trimmed - 1))
  else trimmed
;;

let extract_date_from_text text =
  let pattern = "dddd-dd-dd" in
  let len = String.length text
  and plen = String.length pattern in
  let matches_at i =
    let ok k =
      match pattern.[k], text.[i + k] with
      | 'd', '0' .. '9' -> true
      | 'd', _ -> false
      | expected, actual -> Char.equal expected actual
    in
    let rec go k = k >= plen || (ok k && go (k + 1)) in
    go 0
  in
  let rec scan i =
    if i + plen > len
    then None
    else if matches_at i
    then Some (String.sub text i plen)
    else scan (i + 1)
  in
  scan 0
;;
