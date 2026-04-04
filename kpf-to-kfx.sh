#!/usr/bin/env bash
#
# Bulk convert KPF files to KFX using Calibre + KFX Output plugin.
# Skips files that are already converted.
#
# Prerequisites:
#   - Calibre installed: brew install --cask calibre
#   - KFX Output plugin installed in Calibre
#   - Kindle Previewer 3 installed
#
# Usage:
#   ./kpf-to-kfx.sh ~/manga-kfx ~/manga-kpf/*.kpf
#   ./kpf-to-kfx.sh ~/bleach-kfx ~/bleach-kpf/*.kpf
#
set -euo pipefail

CALIBRE_DEBUG="/Applications/calibre.app/Contents/MacOS/calibre-debug"

die() { printf 'Error: %s\n' "$1" >&2; exit 1; }

[[ $# -ge 2 ]] || die "Usage: $0 <output_dir> <file.kpf> [file.kpf ...]"
[[ -f "$CALIBRE_DEBUG" ]] || die "Calibre not found. Install: brew install --cask calibre"

OUTPUT_DIR="$1"
shift
mkdir -p "$OUTPUT_DIR"

succeeded=0
failed=0
skipped=0

for kpf in "$@"; do
    [[ -f "$kpf" ]] || continue

    basename="$(basename "${kpf%.kpf}")"
    kfx="${OUTPUT_DIR}/${basename}.kfx"

    if [[ -f "$kfx" ]]; then
        echo "  SKIP: ${basename}.kfx (already exists)"
        skipped=$((skipped + 1))
        continue
    fi

    echo "--- Converting: ${basename}.kpf → .kfx ---"

    if "$CALIBRE_DEBUG" -r "KFX Output" -- "$kpf" "$kfx" 2>&1 | grep -E "^(Successfully|WARNING|Features|Metadata)" ; then
        if [[ -f "$kfx" ]]; then
            size=$(du -h "$kfx" | cut -f1)
            echo "  OK: ${basename}.kfx ($size)"
            succeeded=$((succeeded + 1))
        else
            echo "  FAIL: KFX not created" >&2
            failed=$((failed + 1))
        fi
    else
        echo "  FAIL: Conversion error" >&2
        failed=$((failed + 1))
    fi
done

echo ""
echo "=== Done ==="
echo "Converted: $succeeded  Skipped: $skipped  Failed: $failed"
