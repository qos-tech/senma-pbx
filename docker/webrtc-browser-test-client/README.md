# SENMA disposable WebRTC browser harness (TASK-0035C)

Test tooling only. Not the SENMA WebPhone. Not part of production runtime.

- `jssip.bundle.js` — browserify/esbuild bundle of JsSIP 3.10.1 (MIT)
- `index.html` / `app.js` — minimal REGISTER / INVITE / stats UI
- `run.cjs` — Puppeteer-core driver against system Chromium

Credentials must be supplied at runtime. Do not commit real passwords.
