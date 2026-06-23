# Releases — Gem Cascade

## 2026-06-22 — Live on the web + public

- **What deployed:** the Godot 4.6 Web (WASM) export of Gem Cascade, live at
  **https://gemcascade.levelbrook.com**, with the illustrated write-up at
  **https://gemcascade.levelbrook.com/how-it-works.html**.
- **Changed:**
  - Added a Web export preset and exported to `build/web` (single-threaded, so it
    needs no cross-origin-isolation headers).
  - Hosting: a Caddy static container behind the shared reverse proxy on the
    Levelbrook box (Cloudflare Pages can't take the ~36 MB wasm — 25 MiB/file limit).
    Caddy `encode zstd gzip` brings the wasm to ~9 MB on the wire. See
    `deploy-hetzner/`.
  - Cross-linked the repo, the live game, the write-up, and the Levelbrook games
    page (`https://levelbrook.com/game-design/`).
  - Reframed the write-up's "thesis" framing; repo made **public**.
- **How:** `godot --headless --export-release "Web" build/web/index.html` →
  Caddy container + `kamal-proxy deploy … --tls` → DNS A `gemcascade` →
  the box (DNS-only).
- **Verified:** `https://gemcascade.levelbrook.com/` returns HTTP 200; the wasm
  serves `content-encoding: gzip` + `content-type: application/wasm`; loaded in a
  real browser (Chromium) — the board renders and plays with **zero console
  errors**; `how-it-works.html` returns 200.
