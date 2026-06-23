# Releases — Gem Cascade

## 2026-06-23 — Procedural sound effects + demo video

- **What deployed:** a re-export of the Web build to
  **https://gemcascade.levelbrook.com** that now has **sound**, plus a recorded
  gameplay video for the portfolio/job application.
- **Changed:**
  - Added an `Audio` autoload that **synthesizes all eight SFX in GDScript at
    boot** (no audio asset files — same all-shader, asset-free ethos as the
    visuals): select / swap / invalid / match / special-forge / blast / land /
    shuffle. The match cue climbs a semitone per cascade step (the combo ladder).
  - A speaker mute toggle in the HUD; WebAudio unlocks on the first tap.
  - Recorded a 36s self-playing demo (with audio) via a throwaway MovieWriter
    capture harness; artifacts in `~/Desktop/gem-cascade-prep/video/`
    (`gem-cascade-demo.mp4` w/ sound, a muted `gem-cascade-loop.mp4`, a poster).
- **How:** `godot --headless --export-release "Web" build/web/index.html` then
  `rsync build/web/ → root@box:/root/gemcascade/web/` (Caddy serves the live
  volume); `docker restart gemcascade-web`. Video: `godot --write-movie out.avi
  --fixed-fps 60 scenes/_Rec.tscn` → ffmpeg H.264/AAC.
- **Verified:** the re-deployed wasm (37.7 MB, new build) serves
  `content-encoding: gzip` + `content-type: application/wasm`; the audio worklet
  returns 200; loaded the live site in a real browser (Chromium) — **0 page
  errors**, canvas renders and plays; the recorded MP4 has a confirmed AAC audio
  stream produced by the synthesis actually running.

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
