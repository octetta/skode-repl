# skode-repl

[![Gleam](https://img.shields.io/badge/language-Gleam-ffaff3.svg)](https://gleam.run/)
[![Lustre](https://img.shields.io/badge/frontend-Lustre-ff69b4.svg)](https://hexdocs.pm/lustre/)
[![Deploy to GitHub Pages](https://github.com/octetta/skode-repl/actions/workflows/deploy.yml/badge.svg)](https://github.com/octetta/skode-repl/actions/workflows/deploy.yml)

Interactive web REPL and live-coding environment for the **Skred** audio engine and **Skode** music language, built with **Gleam + Lustre** and compiled to WebAssembly.

🌐 **Live REPL:** [octetta.github.io/skode-repl](https://octetta.github.io/skode-repl/)  
📦 **Skred Synthesizer Engine:** [github.com/octetta/pulp](https://github.com/octetta/pulp)  
🌐 **Skred Web Studio:** [octetta.github.io/skred-web](https://octetta.github.io/skred-web/)

---

## Features

- **Live Skode Preview**: Color-coded syntax chips parsing and typing your commands on the fly (voice, pitch, mix, waveform, time, and text).
- **Tab Completion**: Auto-completion and interactive cycling with the Tab key (or the `⇥` button on touch screens).
- **Real-Time WASM Audio Engine**: Multi-threaded WebAssembly audio synthesizer running client-side with low-latency pthread audio streaming.
- **Cross-Origin Isolation**: Automated `coi-serviceworker` integration for instant `SharedArrayBuffer` support on static hosting like GitHub Pages.

---

## Architecture & Code Tour

The core application lives in [`project/`](project/):

- [`project/src/skred_repl.gleam`](project/src/skred_repl.gleam): Lustre reactive application (start/stop engine, history navigation, output stream, live preview chips).
- [`project/src/skode.gleam`](project/src/skode.gleam): Skode / `ands` lexer, AST, typed model, and canonical printer matching upstream `parts/ands.c` in `octetta/pulp`.
- [`project/src/complete.gleam`](project/src/complete.gleam): Pure functional Tab-completion and template candidate matching.
- [`project/src/skred_repl_ffi.mjs`](project/src/skred_repl_ffi.mjs): JavaScript FFI bridge connecting Gleam to the Emscripten WASM module (`skred_api.js`).
- [`project/web/entry.mjs`](project/web/entry.mjs): Application entrypoint bundled into `app.js` with `esbuild`.

---

## Local Development

### Prerequisites
- [Gleam](https://gleam.run/) (`^1.19.2`)
- [Node.js](https://nodejs.org/) (for `esbuild` and local tests)

### Build & Run
```bash
cd project

# Fetch the pinned Skred WASM release assets (skred_api.js & skred_api.wasm)
./fetch-wasm.sh

# Run the test suite
gleam run -m skode_check
gleam run -m complete_check

# Build and bundle
./build.sh

# Serve locally with COOP/COEP headers enabled
./serve-wasm.sh
```
Open `http://localhost:8080` in your browser.

---

## Continuous Deployment

GitHub Pages deployment is automated via [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml):
- **Triggers**:
  - Push to `main` branch.
  - Upstream release dispatches from [`octetta/pulp`](https://github.com/octetta/pulp) (`pulp_release`).
  - Scheduled checks (twice daily) to automatically track new `pulp` releases.
  - Manual trigger via `workflow_dispatch` (with optional explicit version).
- **Build**: Fetches the specified or latest `skred-*-maxed-wasm.zip` release from `octetta/pulp`, builds and tests Gleam sources, bundles `app.js` with `esbuild`, and publishes the static app to [octetta.github.io/skode-repl](https://octetta.github.io/skode-repl/).
