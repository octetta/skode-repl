// esbuild entry for the one-file demo page (run `gleam build` first).
import { main } from "../build/dev/javascript/skred_repl/skred_repl.mjs";
import { plan } from "../build/dev/javascript/skred_repl/skode_js.mjs";
globalThis.skodePlan = plan;
main();
