(** Typst compiler invocation. The site's bundled fonts and the usual system font
    directories are passed with [--font-path]. *)

(** [compile_html ~root ~repo_url ~src] compiles [src] to HTML and returns the document
    written to stdout. Typst warnings only ever go to stderr and are discarded. *)
val compile_html
  :  root:string
  -> repo_url:string
  -> src:string
  -> (string, Error.t) result

(** [compile_pdf ~root ~repo_url ~src ~output] compiles [src] to the PDF file [output]. *)
val compile_pdf
  :  root:string
  -> repo_url:string
  -> src:string
  -> output:string
  -> (unit, Error.t) result
