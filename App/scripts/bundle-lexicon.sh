#!/bin/sh
# Copies the reference lexicon into the app bundle as `lexicon/`.
# Uses the full build (tools/lexicon-build/out, gitignored; run build_lexicon.py --download first)
# when present, otherwise the committed fixture slice so a fresh checkout still builds.
set -eu
ROOT="$SRCROOT/.."
SRC="$ROOT/tools/lexicon-build/out"
if [ ! -f "$SRC/meta.json" ]; then
  SRC="$ROOT/EnglishCore/Fixtures/lexicon"
  echo "warning: full lexicon not built; bundling the fixture slice ($SRC)"
fi
RES="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
DST="$RES/lexicon"
mkdir -p "$DST"
for f in meta.json words.tsv forms.tsv supplementary.txt; do
  cp "$SRC/$f" "$DST/$f"
done
