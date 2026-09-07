(** HTML parsing, sanitization, and text extraction utilities. *)

(** [escape_html text] escapes special HTML characters. *)
val escape_html : string -> string

(** [has_substring ~sub s] checks if substring [sub] is contained in [s]. *)
val has_substring : sub:string -> string -> bool

(** Alias for [has_substring]. *)
val string_contains : sub:string -> string -> bool

(** [add_external_link_targets html] adds target and rel attributes to external links. *)
val add_external_link_targets : string -> string

(** [clean_html_text html] extracts plain text from an HTML fragment. *)
val clean_html_text : string -> string

(** [clean_subtitle html] cleans raw subtitle text from an article. *)
val clean_subtitle : string -> string

(** [clean_authors html] cleans raw author metadata from an article. *)
val clean_authors : string -> string

(** [clean_tag_name tag] strips leading '#' and trims whitespace from [tag]. *)
val clean_tag_name : string -> string

(** [extract_date_from_text text] scans [text] for a YYYY-MM-DD date pattern. *)
val extract_date_from_text : string -> string option
