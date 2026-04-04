#!/usr/bin/env bash
#
# Convert comics/manga for Kindle Scribe Colorsoft.
#
# Output formats:
#   PDF (default) — no blank pages, smooth page turns, Send to Kindle
#   KFX (-K)      — no blank pages + proper manga R2L, requires USB sideload
#
# PDF mode: original images preserved. Use -O to smart-compress.
# KFX mode: builds EPUB with go-comic-converter, then converts via Calibre + KFX Output.
#
# PDFs auto-split at 200 MB (Send to Kindle web limit).
#
# Usage:
#   ./kindle-pdf.sh mycomic.cbz                  # PDF, left-to-right
#   ./kindle-pdf.sh -m manga.cbz                 # PDF, manga (R2L metadata only)
#   ./kindle-pdf.sh -K -m manga.cbz              # KFX, proper manga R2L
#   ./kindle-pdf.sh -c 1.15 -m manga.cbz         # PDF with contrast boost
#   ./kindle-pdf.sh -O -m large-manga.cbz        # PDF, optimized file size
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON="${COMIC_PDF_PYTHON:-${HOME}/.local/share/kcc/.venv/bin/python3}"
COMIC_TO_PDF="${SCRIPT_DIR}/comic-to-pdf.py"
GO_COMIC_CONVERTER="${SCRIPT_DIR}/go-comic-converter"
CALIBRE_DEBUG="/Applications/calibre.app/Contents/MacOS/calibre-debug"

die() { printf 'Error: %s\n' "$1" >&2; exit 1; }

PDF_ARGS=()
KFX_MODE=false
MANGA=false
CONTRAST=""

while [[ "${1:-}" == -* ]]; do
    case "$1" in
        -m|--manga)     PDF_ARGS+=(--manga); MANGA=true; shift ;;
        -K|--kfx)       KFX_MODE=true; shift ;;
        -O|--optimize)  PDF_ARGS+=(--optimize); shift ;;
        -q|--quality)   PDF_ARGS+=(--quality "$2"); shift 2 ;;
        -c|--contrast)  PDF_ARGS+=(--contrast "$2"); CONTRAST="$2"; shift 2 ;;
        --max-mb)       PDF_ARGS+=(--max-mb "$2"); shift 2 ;;
        -h|--help)
            echo "Usage: $0 [options] <file|dir> [...]"
            echo ""
            echo "Options:"
            echo "  -m, --manga       Manga mode (right-to-left)"
            echo "  -K, --kfx         Output KFX instead of PDF (requires Calibre + Kindle Previewer)"
            echo "  -O, --optimize    Smart compress (color PNG → JPEG)"
            echo "  -q, --quality N   JPEG quality for --optimize/--contrast (default: 90)"
            echo "  -c, --contrast N  Contrast adjustment: 1.0=original, 1.15=e-ink recommended"
            echo "  --max-mb N        Split PDFs at N MB (default: 200, 0=no split)"
            exit 0
            ;;
        *) die "Unknown option: $1" ;;
    esac
done

[[ $# -ge 1 ]] || die "Usage: $0 [-m] [-K] [-O] [-c N] [-q N] <file|dir> [...]"

if [[ "$KFX_MODE" == true ]]; then
    # KFX mode: EPUB → KFX via Calibre
    [[ -f "$GO_COMIC_CONVERTER" ]] || die "go-comic-converter not found. Run: go build -o go-comic-converter ."
    [[ -f "$CALIBRE_DEBUG" ]] || die "Calibre not found. Install: brew install --cask calibre"

    succeeded=0
    failed=0

    for input in "$@"; do
        base="${input%.*}"
        epub="${base}.epub"
        kfx="${base}.kfx"

        echo "--- Converting to KFX: $(basename "$input") ---"

        # Step 1: Build EPUB with go-comic-converter
        GCC_ARGS=(-input "$input" -profile KSC -quality 90 -grayscale=false -crop=false
                  -portrait-only -autosplitdoublepage -titlepage 0 -aspect-ratio -1
                  -hascover=false)
        [[ "$MANGA" == true ]] && GCC_ARGS+=(-manga)

        rm -f "$epub"
        if ! "$GO_COMIC_CONVERTER" "${GCC_ARGS[@]}" 2>&1; then
            echo "  FAILED: EPUB creation failed" >&2
            failed=$((failed + 1))
            continue
        fi

        # Step 2: Convert EPUB → KFX via Calibre + KFX Output plugin
        rm -f "$kfx"
        if ! "$CALIBRE_DEBUG" -r "KFX Output" -- "$epub" "$kfx" 2>&1; then
            echo "  FAILED: KFX conversion failed. Is Kindle Previewer 3 installed?" >&2
            failed=$((failed + 1))
            continue
        fi

        # Clean up intermediate EPUB
        rm -f "$epub"

        if [[ -f "$kfx" ]]; then
            size=$(du -h "$kfx" | cut -f1)
            echo "  OK: $kfx ($size)"
            succeeded=$((succeeded + 1))
        else
            echo "  FAILED: KFX was not created" >&2
            failed=$((failed + 1))
        fi
    done

    echo ""
    echo "=== Summary ==="
    echo "Total: $((succeeded + failed))  Succeeded: $succeeded  Failed: $failed"
    [[ $failed -eq 0 ]] || exit 1
else
    # PDF mode
    [[ -f "$COMIC_TO_PDF" ]] || die "comic-to-pdf.py not found in ${SCRIPT_DIR}"
    [[ -x "$PYTHON" ]] || die "Python not found at ${PYTHON}. Set COMIC_PDF_PYTHON."
    exec "$PYTHON" "$COMIC_TO_PDF" "${PDF_ARGS[@]}" "$@"
fi
