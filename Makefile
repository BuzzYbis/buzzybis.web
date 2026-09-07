# BuzzYbis static site: build, fetch, serve.

DUNE         := dune
DUNE_ROOT    := --root .
FETCH        := $(DUNE) exec $(DUNE_ROOT) -- bin/fetch.exe
SERVE        := $(DUNE) exec $(DUNE_ROOT) -- bin/serve.exe
PORT         ?= 8000
BUILD_DIR    := build
SITE_TMP     := _site_tmp
# External projects directory, read from projects.toml (override: make PROJECTS_DIR=...).
PROJECTS_DIR ?= $(or $(shell sed -n 's/^projects_dir *= *"\(.*\)".*/\1/p' projects.toml),../buzzybis_projects)

.PHONY: all build fetch fetch-force watch serve test fmt format clean

all: build

# Regenerate the OCaml-produced pages, assemble a staging copy of site/ plus the external
# project HTML/PDF assets, and run Soupault on it.
build:
	$(FETCH) --pages-only
	rm -rf $(SITE_TMP)
	mkdir -p $(SITE_TMP)
	cp -R site/. $(SITE_TMP)/
	rm -rf $(SITE_TMP)/project
	mkdir -p $(SITE_TMP)/project
	[ ! -f $(SITE_TMP)/project.html ] || mv $(SITE_TMP)/project.html $(SITE_TMP)/project/index.html
	[ ! -f $(PROJECTS_DIR)/resume.pdf ] || cp $(PROJECTS_DIR)/resume.pdf $(SITE_TMP)/resume.pdf
	@for proj_dir in $(PROJECTS_DIR)/*/; do \
		[ -d "$$proj_dir" ] || continue; \
		proj=$$(basename "$$proj_dir"); \
		mkdir -p "$(SITE_TMP)/project/$$proj"; \
		for sub in html pdfs; do \
			[ ! -d "$$proj_dir/$$sub" ] || cp -R "$$proj_dir/$$sub" "$(SITE_TMP)/project/$$proj/"; \
		done; \
		rm -rf "$(SITE_TMP)/project/$$proj/html/cached_pdf"; \
	done
	soupault --site-dir $(SITE_TMP) --build-dir $(BUILD_DIR)
	rm -rf $(SITE_TMP)

# Fetch blog posts from GitHub; only recompiles projects whose remote changed.
fetch:
	$(FETCH)

# Refetch and recompile everything even if commit SHAs match.
fetch-force:
	$(FETCH) --force

# Poll GitHub periodically and rebuild the site on changes.
watch:
	$(FETCH) --watch

# Build, then serve $(BUILD_DIR) locally with the OCaml HTTP server.
serve: build
	$(SERVE) $(PORT)

test:
	$(DUNE) test $(DUNE_ROOT)

fmt format:
	$(DUNE) fmt $(DUNE_ROOT)

clean:
	rm -rf $(BUILD_DIR) .soupault-cache $(SITE_TMP)
	$(DUNE) clean $(DUNE_ROOT)
