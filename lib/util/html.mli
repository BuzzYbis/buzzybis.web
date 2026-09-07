(** HTML escaping, parsing and text extraction. *)

(** [escape_html s] escapes the ampersand, angle brackets and both quote characters so
    that [s] can be embedded in HTML text or attribute values. *)
val escape_html : string -> string

(** [set_external_link_targets soup] adds [target="_blank"] and
    [rel="noopener noreferrer"] to every [http(s)] anchor in [soup], in place. *)
val set_external_link_targets : Soup.soup Soup.node -> unit

(** [text_content node] concatenates and trims the text nodes under [node]. *)
val text_content : 'a Soup.node -> string

(** [clean_authors html] renders an author list as escaped HTML, preserving links. A
    leading [By] prefix is dropped. *)
val clean_authors : string -> string

(** [clean_tag_name tag] strips a leading ['#'] and surrounding whitespace. *)
val clean_tag_name : string -> string

(** [extract_date_from_text text] finds the first [YYYY-MM-DD] substring of [text]. *)
val extract_date_from_text : string -> string option
