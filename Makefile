# BuzzYbis Static Site Build & Management
.PHONY: all build fetch fetch-force watch serve clean

all: build

# Build OCaml binaries with Dune and generate static site with Soupault.
# Uses an isolated staging directory (_site_tmp) to assemble site/ files, the
# project directory index, and external project assets without polluting the repository.
build:
	dune build --root .
	dune exec --root . -- bin/fetch.exe --pages-only
	@rm -rf _site_tmp && mkdir -p _site_tmp
	@cp -R site/* _site_tmp/
	@rm -rf _site_tmp/project
	@mkdir -p _site_tmp/project
	@if [ -f _site_tmp/project.html ]; then mv _site_tmp/project.html _site_tmp/project/index.html; fi
	@if [ -f ../buzzybis_projects/resume.pdf ]; then cp ../buzzybis_projects/resume.pdf _site_tmp/resume.pdf; fi
	@rm -f ../buzzybis_projects/*/*.html 2>/dev/null || true
	@for proj_dir in ../buzzybis_projects/*; do \
		if [ -d "$$proj_dir" ]; then \
			proj=$$(basename "$$proj_dir"); \
			mkdir -p _site_tmp/project/$$proj; \
			if [ -d "$$proj_dir/html" ]; then cp -R "$$proj_dir/html" _site_tmp/project/$$proj/; fi; \
			if [ -d "$$proj_dir/pdfs" ]; then cp -R "$$proj_dir/pdfs" _site_tmp/project/$$proj/; fi; \
			rm -rf _site_tmp/project/$$proj/html/cached_pdf 2>/dev/null || true; \
		fi; \
	done
	@soupault --site-dir _site_tmp --build-dir build
	@rm -rf _site_tmp

# Fetch blogposts from public GitHub repositories using OCaml (only rebuilds if remote changed)
fetch:
	dune exec --root . -- bin/fetch.exe

# Force refetch and recompile even if commit SHAs match
fetch-force:
	dune exec --root . -- bin/fetch.exe -- --force

# Run background polling daemon to check for updates periodically and auto-rebuild
watch:
	dune exec --root . -- bin/fetch.exe -- --watch

# Serve the static website locally with pure OCaml HTTP server
serve: build
	dune exec --root . -- bin/serve.exe 8000

# Clean generated artifacts, caches, and external project symlink
clean:
	rm -rf build .soupault-cache site/project _site_tmp
	dune clean --root .

# Format OCaml source code with ocamlformat
fmt format:
	dune fmt
