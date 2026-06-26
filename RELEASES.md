# Releases — Gem Cascade

## 2026-06-26 — "Mega juice" spectacle pass (v2): voice announcer, real assets, bloom

- **What deployed:** a re-export of the Web build to
  **https://gemcascade.levelbrook.com**, re-skinned for maximum *visual + audible*
  spectacle — the "speak the producer's language" pass (a match-3 buyer judges a
  35-second clip on jaw-drop, not engineering elegance).
- **Changed:**
  - **Excited voice announcer** — real recorded callouts (free Hume Octave neural
    TTS, bundled as 16 `.ogg`): "Let's go!", "Nice!", "Amazing!", "Unstoppable!",
    "Gem Cascade!", "Ka-boom!"… An escalating tier system fires a bigger shout +
    bigger on-screen text as combos climb (`scripts/Announcer.gd`).
  - **Big punchy combo text** in a chunky arcade display font (Luckiest Guy /
    Bungee, OFL) — scale-punch in, hold, fly up + fade; colour escalates by tier.
  - **Bloom / glow** — every gem now carries an additive coloured glow halo (reads
    as bloom on the web compatibility renderer, no HDR post-process needed); pops
    flare the halo huge and white.
  - **Mega particle juice** — textured spark-stars + tumbling gem shards + soft
    additive puffs on every clear; expanding **shockwave rings** scaled to clear
    size and combo depth.
  - **Hit-stop** (brief world-freeze) on meaty clears, **trauma-based decaying
    screen shake**, full-screen colour **flash**, squash-and-stretch on gem landing.
  - **Synthesized music** — an upbeat seamless looping soundtrack (bass + arpeggio
    + pad + kick/hat groove) built in GDScript at boot (`scripts/Music.gd`); ducks
    when a blast goes off. Mute toggle now silences sfx + voice + music together.
  - Richer background shader (drifting nebula + twinkling star field + vignette).
  - New CC0/own assets under `assets/` (5 VFX textures, 3 OFL fonts, 16 voice .ogg).
  - Recorded a **32 s self-playing demo with sound** (announcer + music + sfx) via a
    throwaway MovieWriter harness; artifacts in `~/Desktop/gem-cascade-prep/video/`
    (`gem-cascade-v2-demo.mp4`, a silent `gem-cascade-v2-loop.mp4`, a poster).
- **How:** `godot --headless --export-release "Web" build/web/index.html` then
  `rsync build/web/ → root@5.78.108.109:/root/gemcascade/web/` (Caddy serves the
  live volume) + `docker restart gemcascade-web`. Video: `godot --write-movie
  out.avi --fixed-fps 60 res://_Movie.tscn` → ffmpeg H.264/AAC, AVI deleted after.
- **Verified:** served `index.pck` byte-size matches the local build exactly
  (765,260 B); wasm 200 + `content-encoding: gzip` + `content-type:
  application/wasm`; loaded the live site in real Chromium (1223) — **0 page
  errors, 0 failed requests**, canvas renders. The recorded MP4 has a confirmed
  AAC stream (announcer/music actually ran), 32.1 s. Self-playing screenshot pass
  captured the "EXCELLENT!"/blast spectacle on the real display before deploy.

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
