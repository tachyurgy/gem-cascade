# Web deploy — gemcascade.levelbrook.com

The live build is a Godot 4 **Web (HTML5/WASM)** export served as static files by a
tiny **Caddy** container behind a shared reverse proxy.

Why not Cloudflare Pages: the Godot engine `index.wasm` is ~36 MB and Pages enforces
a 25 MiB per-file limit. (Pre-gzipping the wasm and declaring `Content-Encoding: gzip`
in `_headers` does **not** work — Pages strips that header, so the browser receives
gzip bytes and `WebAssembly.instantiateStreaming` fails with a bad magic word.) A
plain static origin that compresses on the fly avoids the whole problem.

## Build

```bash
godot --headless --export-release "Web" build/web/index.html
cp docs/HOW-IT-WORKS.html build/web/how-it-works.html
cp docs/screenshot.png     build/web/screenshot.png
```

(Requires the Godot 4.6 **Web** export template installed.)

## Serve

`Caddyfile` (in this folder) roots the export, answers `/up` for health checks, and
`encode zstd gzip` compresses the 36 MB wasm down to ~9 MB on the wire. Run it as a
container on the proxy's network and register the host route + TLS with the proxy:

```bash
docker run -d --name gemcascade-web --restart unless-stopped --network kamal \
  -v /srv/gemcascade/web:/srv:ro -v /srv/gemcascade/Caddyfile:/etc/caddy/Caddyfile:ro \
  caddy:2-alpine
# register with the running kamal-proxy (Let's Encrypt TLS):
kamal-proxy deploy gemcascade --target gemcascade-web:80 \
  --host gemcascade.levelbrook.com --tls
```

Caddy serves `.wasm` as `application/wasm`; the proxy passes `Content-Encoding`
through unchanged, so the browser decompresses transparently.
