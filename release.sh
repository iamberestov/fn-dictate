#!/usr/bin/env bash
# Builds the app and packs it into dist/FnDictate.app.zip, the file the npx installer unpacks.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
mkdir -p dist
rm -f dist/FnDictate.app.zip
ditto -c -k --keepParent build/FnDictate.app dist/FnDictate.app.zip
echo "packed dist/FnDictate.app.zip ($(du -h dist/FnDictate.app.zip | cut -f1))"
