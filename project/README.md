# skred-lustre

Core REPL of octetta/skred-web in Gleam + Lustre, with a live Skode preview and Tab completion (Tab key, or the ⇥ button on phones).

- `src/skred_repl.gleam` : Lustre app (start/stop, history, preview chips)
- `src/skode.gleam`      : Skode/ands lexer + typed model + printer, following parts/ands.c in octetta/pulp
- `src/skode_check.gleam`: `gleam run -m skode_check` (51 checks: sentinels, arrays, comments, defers incl. spaced, bare sigils, strings, macros, round trips)
- `src/skode_js.gleam`    : bridge for the browser stand-in engine (`plan` turns Skode into delay/kind/value lines)
- `web/`                 : `shim.js` (Web Audio stand-in for the skred `Module`) and `entry.mjs` (esbuild entry for a one-file page)
- `src/skred_repl_ffi.mjs`: bridge to the skred WASM `Module` (calls as in skred-web's help.html)
- `src/complete.gleam`   : pure Tab-completion logic (candidates, common prefix)
- `src/complete_check.gleam`: `gleam run -m complete_check` exercises Tab behaviour
- `src/view_check.gleam` : `gleam run -m view_check` prints the view as HTML (no browser needed)

Verified: compiled against lustre 5.7.1 + stdlib 1.0.5 (via git deps), view rendered in Node.
Not verified: running in a browser against the real WASM engine.

## Run
1. In a skred-web clone: `./fetch-wasm.sh`, then copy this folder's files in
   (rename index.html if it collides with skred-web's).
2. `gleam build`
3. `./serve-wasm.sh` and open http://localhost:8080

## C parser alignment
`src/skode.gleam` follows the *fixed* C `ands` parser (see `antigravity-prompt.md` and the two patches):
blanks after `+`/`~` are accepted when an amount follows, `&` takes digits only, and a bare `$`/`&` never
swallows the next character. `skode.defer_blanks` (a const) turns the blank tolerance off to preview
against an engine built before the fix.

## One-file demo page
`gleam build`, then bundle `web/entry.mjs` with esbuild (`--bundle --minify --format=iife`) and inline it
after `web/shim.js`. With the real engine, use `index.html` + skred_api.js instead of the shim.
