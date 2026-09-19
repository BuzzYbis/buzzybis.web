# BuzzYbis Web

A lightweight, high-performance static + dynamic website and blog engine built with **OCaml**, **Typst**, and **Soupault**.

---

## Features

- **Automated Repository Synchronization**: Periodically polls GitHub for new or updated Typst articles (`blog/*.typ`) and compiles them to HTML.
- **E-Ink Minimalist Design**: High-contrast, warm-tinted e-ink color palette engineered for readability and accessibility (WCAG AAA compliant).
- **On-Demand PDF Compilation**: Generates customized Typst article PDFs on the fly with local caching, concurrency locking, and TTL cache eviction.
- **PDFs Opened, Not Downloaded**: Article and project PDFs open in a new tab, in the browser's own PDF viewer, which provides the download and print controls.
- **Modern Semantic HTML**: Uses Soupault for clean index views, metadata extraction, and static page generation.

---

## Quick Start (Development)

### Prerequisites

- OCaml `>= 5.1` & OPAM
- Dune `>= 3.13`
- Typst `>= 0.12.0`
- Soupault `>= 5.2.0`
- External libraries: `dune`, `yojson`, `uri`, `lambdasoup`, `async_log`

```bash
# Install dependencies
opam install . --deps-only -y

# Build the site distribution
make build

# Launch the local HTTP server on port 8000
make serve
```

---

## Production Deployment

For complete instructions on putting BuzzYbis Web into production (including VPS with systemd, Docker containerization, Caddy/Nginx reverse proxy configs, and GitHub Actions CI/CD), see:

👉 **[PRODUCTION.md](PRODUCTION.md)**

---

## License

[MIT](LICENSE.md)
