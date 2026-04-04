#!/usr/bin/env bash
#
# Batch convert manga/comics to KFX for Kindle Scribe Colorsoft.
# Pipeline: CBZ → Images → Kindle Create (KPF) → KFX
#
# Usage:
#   ./batch-to-kfx.sh ~/Downloads/bleach-images ~/Downloads/bleach-kpf ~/Downloads/bleach-kfx
#
# Args:
#   $1 = images directory (parent of per-volume folders with numbered images)
#   $2 = KPF output directory (from Kindle Create)
#   $3 = KFX output directory (final output)
#
# Steps:
#   1. Run Kindle Create automation (if KPFs don't exist)
#   2. Convert all KPFs to KFX via Calibre
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CALIBRE_DEBUG="/Applications/calibre.app/Contents/MacOS/calibre-debug"

die() { printf 'Error: %s\n' "$1" >&2; exit 1; }

[[ $# -ge 3 ]] || die "Usage: $0 <images_dir> <kpf_dir> <kfx_dir>"

IMAGES_DIR="$1"
KPF_DIR="$2"
KFX_DIR="$3"

mkdir -p "$KPF_DIR" "$KFX_DIR"

# Step 1: Kindle Create automation (Images → KPF)
echo "=== Step 1: Kindle Create (KPF generation) ==="

total_vols=$(ls -d "$IMAGES_DIR"/*/ 2>/dev/null | wc -l | tr -d ' ')
existing_kpfs=$(ls "$KPF_DIR"/*.kpf 2>/dev/null | wc -l | tr -d ' ')
echo "Volumes: $total_vols  KPFs found: $existing_kpfs"

if [[ "$existing_kpfs" -lt "$total_vols" ]]; then
    echo ""
    echo "Missing KPFs. Running Kindle Create automation..."
    echo "(Make sure Kindle Create is open on the Start screen)"
    echo ""
    "${SCRIPT_DIR}/kindle-create-batch.sh" "$IMAGES_DIR" "$KPF_DIR" "${AUTHOR:-}" "${PUBLISHER:-}"
    existing_kpfs=$(ls "$KPF_DIR"/*.kpf 2>/dev/null | wc -l | tr -d ' ')
    echo "KPFs after automation: $existing_kpfs"
else
    echo "All KPFs present."
fi

# Step 2: Convert KPFs to KFX
echo ""
echo "=== Step 2: Converting KPF → KFX ==="

[[ -f "$CALIBRE_DEBUG" ]] || die "Calibre not found at $CALIBRE_DEBUG"

succeeded=0
failed=0
skipped=0

for kpf in "$KPF_DIR"/*.kpf; do
    [[ -f "$kpf" ]] || continue

    basename="$(basename "${kpf%.kpf}")"
    kfx="${KFX_DIR}/${basename}.kfx"

    if [[ -f "$kfx" ]]; then
        echo "  SKIP: ${basename}.kfx (already exists)"
        skipped=$((skipped + 1))
        continue
    fi

    echo "--- Converting: ${basename} ---"

    if "$CALIBRE_DEBUG" -r "KFX Output" -- "$kpf" "$kfx" 2>&1 | tail -3; then
        if [[ -f "$kfx" ]]; then
            size=$(du -h "$kfx" | cut -f1)
            echo "  OK: ${basename}.kfx ($size)"
            succeeded=$((succeeded + 1))
        else
            echo "  FAILED: KFX not created" >&2
            failed=$((failed + 1))
        fi
    else
        echo "  FAILED: Conversion error" >&2
        failed=$((failed + 1))
    fi
done

echo ""
echo "=== Summary ==="
echo "Converted: $succeeded  Failed: $failed  Skipped: $skipped"
[[ $failed -eq 0 ]] || exit 1
