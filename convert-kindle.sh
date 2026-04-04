#!/usr/bin/env bash
#
# Convert comic files (CBR, CBZ, PDF) for Kindle devices using KCC.
# Produces EPUB for Send to Kindle (web upload, 200MB limit).
#
# Defaults: Kindle Scribe Colorsoft (KSCS, 1986x2648), JPEG quality 90,
#           cropping disabled (prevents blank pages on Scribe hardware).
#
# Device flags:
#   -scs|-scribe-colorsoft  Kindle Scribe Colorsoft (default)
#   -s|-scribe              Kindle Scribe (1860x2480)
#   -cs|-colorsoft          Kindle Colorsoft 7" (1264x1680, crop enabled)
#
# Options:
#   -mg|-manga              Manga mode (right-to-left)
#   -np|-nocrop             Disable cropping (default for Scribe devices)
#   -crop                   Force enable cropping
#   -q|--quality <1-100>    JPEG quality (default: 90)
#
# Usage:
#   ./convert-kindle.sh mycomic.cbr
#   ./convert-kindle.sh -mg manga-vol1.cbz
#   ./convert-kindle.sh -s -crop mycomic.cbr
#   ./convert-kindle.sh -cs ./comics-directory/
#
set -euo pipefail

KCC_C2E="${KCC_C2E:-$HOME/.local/share/kcc/.venv/bin/kcc-c2e}"
KCC_PROFILE="KSCS"
KCC_QUALITY=90
KCC_CROP_DISABLE=true
KCC_ARGS=()

# --- helpers (must be defined before flag parsing) ---
die() { printf 'Error: %s\n' "$1" >&2; exit 1; }

# Parse flags
while [[ "${1:-}" == -* ]]; do
    case "$1" in
        -cs|-colorsoft)             KCC_PROFILE="KCS"; KCC_CROP_DISABLE=false; shift ;;
        -s|-scribe)                KCC_PROFILE="KS"; shift ;;
        -scs|-scribe-colorsoft)    KCC_PROFILE="KSCS"; shift ;;
        -mg|-manga)                KCC_ARGS+=(-m); shift ;;
        -np|-nocrop)               KCC_CROP_DISABLE=true; shift ;;
        -crop)                     KCC_CROP_DISABLE=false; shift ;;
        -q|--quality)              KCC_QUALITY="$2"; shift 2 ;;
        *) die "Unknown option: $1" ;;
    esac
done

# Disable cropping for Scribe devices (prevents blank/cut-off pages)
if [[ "$KCC_CROP_DISABLE" == true ]]; then
    KCC_ARGS+=(-c 0)
fi

# Always: color, EPUB, no kepub ext, split at 200MB (Send to Kindle web limit)
KCC_ARGS+=(--forcecolor -f EPUB --nokepub --jpeg-quality "$KCC_QUALITY" --ts 200)

check_deps() {
    local kcc_bin="${KCC_C2E%% *}"
    command -v "$kcc_bin" >/dev/null 2>&1 \
        || die "KCC not found. Install it or set KCC_C2E."
    command -v 7zz >/dev/null 2>&1 || command -v 7z >/dev/null 2>&1 \
        || die "7z/7zz not found. Install with: brew install 7zip p7zip"
}

convert_one() {
    local input="$1"
    local base dir

    if [[ -d "$input" ]]; then
        base="${input%/}"
        dir="$(dirname "$base")"
    else
        base="${input%.*}"
        dir="$(dirname "$input")"
    fi

    echo "--- Converting: $input ---"

    local epub="${base}.epub"

    $KCC_C2E -p "$KCC_PROFILE" "${KCC_ARGS[@]}" -o "$dir" "$input"

    if [[ ! -f "$epub" ]]; then
        # KCC sometimes appends _kccN suffix
        local basename
        basename="$(basename "$base")"
        local kcc_output
        kcc_output="$(find "$dir" -maxdepth 1 -name "${basename}_kcc*.epub" -print -quit 2>/dev/null)"

        if [[ -n "$kcc_output" && -f "$kcc_output" ]]; then
            mv "$kcc_output" "$epub"
        else
            echo "  FAILED: EPUB was not created for $input" >&2
            return 1
        fi
    fi

    echo "  OK: $epub"
    return 0
}

# --- main ---
[[ $# -ge 1 ]] || die "Usage: $0 [-cs|-s|-scs] [-mg] [-np|-crop] [-q N] <file|dir> [...]"
check_deps

succeeded=0
failed=0
total=0

for arg in "$@"; do
    files=()

    if [[ -d "$arg" ]]; then
        # Batch mode: collect supported files inside the directory.
        while IFS= read -r -d '' f; do
            files+=("$f")
        done < <(find "$arg" -maxdepth 1 -type f \( \
            -iname '*.cbr' -o -iname '*.cbz' -o -iname '*.pdf' \
            -o -iname '*.zip' -o -iname '*.rar' \
        \) -print0 | sort -z)

        if [[ ${#files[@]} -eq 0 ]]; then
            echo "No supported files found in $arg" >&2
            continue
        fi
    elif [[ -f "$arg" ]]; then
        files=("$arg")
    else
        echo "Skipping $arg: not a file or directory" >&2
        continue
    fi

    for f in "${files[@]}"; do
        total=$((total + 1))
        if convert_one "$f"; then
            succeeded=$((succeeded + 1))
        else
            failed=$((failed + 1))
        fi
    done
done

echo ""
echo "=== Summary ==="
echo "Total: $total  Succeeded: $succeeded  Failed: $failed"

[[ $failed -eq 0 ]] || exit 1
