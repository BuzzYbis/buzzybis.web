(lang dune 3.13)

(name buzzybis_web)

(generate_opam_files true)

(package
 (name buzzybis_web)
 (synopsis "Static site generator and local HTTP server for buzzybis.web")
 (description
  "Fetches Typst blog posts from GitHub, compiles them to HTML, generates the\n   project and home pages consumed by Soupault, and serves the built site\n   locally with on-demand PDF compilation.")
 (depends
  (ocaml
   (>= 5.1))
  dune
  yojson
  uri
  lambdasoup
  async_log))
