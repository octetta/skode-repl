#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "==> Fetching WASM assets if needed..."
if [ ! -f "skred_api.wasm" ]; then
  ./fetch-wasm.sh
fi

echo "==> Compiling Gleam code..."
gleam build --target javascript

echo "==> Bundling app.js with esbuild..."
npx esbuild web/entry.mjs --bundle --minify --format=esm --outfile=app.js

echo "==> Preparing dist/ directory..."
mkdir -p dist
cp index.html coi-serviceworker.min.js skred_api.js skred_api.wasm app.js dist/

echo "==> Build complete! Output in dist/"
