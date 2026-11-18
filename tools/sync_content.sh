#!/bin/sh
# Rebuilds course content from its sources and copies it into the app bundle folder.
# Usage: tools/sync_content.sh            (run from anywhere)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
node "$ROOT/tools/content/build_content.mjs" "$@"
DEST="$ROOT/ios/MasteryAcademy/Resources/Content"
mkdir -p "$DEST"
cp "$ROOT"/content/build/catalog.json "$ROOT"/content/build/course-*.json "$ROOT"/content/build/web-*.html "$DEST"/
echo "copied $(ls "$DEST" | wc -l | tr -d ' ') files to ios/MasteryAcademy/Resources/Content"
