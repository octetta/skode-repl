#!/bin/bash
# Downloads the pinned skred WASM engine (skred_api.js + skred_api.wasm)
# into this directory, next to index.html.
set -e
cd "$(dirname "$0")"
VERSION=$(cat WASM_VERSION.txt)
echo "Fetching skred WASM v${VERSION}..."
curl -fL -o wasm.zip "https://github.com/octetta/sk3/releases/download/v${VERSION}/skred-${VERSION}-maxed-wasm.zip"
unzip -o wasm.zip "skred-${VERSION}-maxed/*"
mv skred-${VERSION}-maxed/skred_api.* .
rm -rf "skred-${VERSION}-maxed" wasm.zip
echo "Done: $(ls skred_api.*)"
