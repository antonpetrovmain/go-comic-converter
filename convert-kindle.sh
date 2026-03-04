#!/usr/bin/env bash
#
# Convert comic files (CBR, CBZ, PDF, or image directories) to Kindle Colorsoft AZW3.
# Uses go-comic-converter (-> EPUB) then Calibre's ebook-convert (-> AZW3).
#
# Usage:
#   ./convert-kindle.sh mycomic.cbr
#   ./convert-kindle.sh ./comics-directory/
#
set -euo pipefail

GO_COMIC_CONVERTER="${GO_COMIC_CONVERTER:-go-comic-converter}"
EBOOK_CONVERT="${EBOOK_CONVERT:-ebook-convert}"
PROFILE="KSC"

# --- helpers ---
die() { printf 'Error: %s\n' "$1" >&2; exit 1; }

check_deps() {
    command -v "$GO_COMIC_CONVERTER" >/dev/null 2>&1 \
        || die "go-comic-converter not found in PATH. Install it or set GO_COMIC_CONVERTER."
    command -v "$EBOOK_CONVERT" >/dev/null 2>&1 \
        || die "ebook-convert (Calibre) not found in PATH. Install it or set EBOOK_CONVERT."
}

# Convert a single input (file or image directory) to AZW3.
convert_one() {
    local input="$1"
    local base

    if [[ -d "$input" ]]; then
        # For directories, strip trailing slashes to derive the name.
        base="${input%/}"
    else
        # Strip extension for files.
        base="${input%.*}"
    fi

    local epub="${base}.epub"
    local azw3="${base}.azw3"

    echo "--- Converting: $input ---"

    # Step 1: comic -> EPUB
    "$GO_COMIC_CONVERTER" \
        -profile "$PROFILE" \
        -grayscale=false \
        -input "$input" \
        -output "$epub"

    if [[ ! -f "$epub" ]]; then
        echo "  FAILED: EPUB was not created for $input" >&2
        return 1
    fi

    # Step 2: EPUB -> AZW3
    "$EBOOK_CONVERT" "$epub" "$azw3"

    if [[ ! -f "$azw3" ]]; then
        echo "  FAILED: AZW3 was not created for $input" >&2
        return 1
    fi

    # Step 3: clean up intermediate EPUB
    rm -f "$epub"

    echo "  OK: $azw3"
    return 0
}

# --- main ---
[[ $# -ge 1 ]] || die "Usage: $0 <file|directory> [file|directory ...]"
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
