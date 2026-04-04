#!/usr/bin/env bash
#
# Extract images from CBZ/CBR/ZIP/RAR files into numbered sequential files
# for import into Kindle Create.
#
# Output: <output_dir>/<volume_name>/0001.png, 0002.png, etc.
#
# Usage:
#   ./extract-images.sh ~/manga-images ~/manga/*.cbz
#   ./extract-images.sh ~/bleach-images ~/bleach/*.cbz
#
set -euo pipefail

die() { printf 'Error: %s\n' "$1" >&2; exit 1; }

[[ $# -ge 2 ]] || die "Usage: $0 <output_dir> <file.cbz> [file.cbz ...]"

OUTPUT_DIR="$1"
shift
mkdir -p "$OUTPUT_DIR"

succeeded=0
failed=0
skipped=0

for input in "$@"; do
    basename="$(basename "${input%.*}")"
    vol_dir="${OUTPUT_DIR}/${basename}"
    ext="${input##*.}"
    ext_lower="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"

    # Skip if already extracted
    if [[ -d "$vol_dir" ]] && [[ -n "$(ls -A "$vol_dir" 2>/dev/null)" ]]; then
        echo "  SKIP: ${basename} (already extracted)"
        skipped=$((skipped + 1))
        continue
    fi

    echo "--- Extracting: $(basename "$input") ---"

    tmp_dir="$(mktemp -d)"

    case "$ext_lower" in
        cbz|zip)
            unzip -q -o "$input" -d "$tmp_dir" 2>/dev/null
            ;;
        cbr|rar)
            if command -v unrar &>/dev/null; then
                unrar x -o+ -y "$input" "$tmp_dir/" &>/dev/null
            elif command -v 7zz &>/dev/null; then
                7zz x "-o${tmp_dir}" -y "$input" &>/dev/null
            elif command -v 7z &>/dev/null; then
                7z x "-o${tmp_dir}" -y "$input" &>/dev/null
            else
                echo "  FAIL: No RAR extractor (install: brew install --cask rar)" >&2
                failed=$((failed + 1))
                rm -rf "$tmp_dir"
                continue
            fi
            ;;
        *)
            echo "  FAIL: Unsupported format: $ext" >&2
            failed=$((failed + 1))
            rm -rf "$tmp_dir"
            continue
            ;;
    esac

    # Collect and sort image files
    images=()
    while IFS= read -r -d '' f; do
        images+=("$f")
    done < <(find "$tmp_dir" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.tiff' -o -iname '*.bmp' -o -iname '*.gif' \) ! -name '.*' -print0 | sort -z)

    if [[ ${#images[@]} -eq 0 ]]; then
        echo "  FAIL: No images found" >&2
        failed=$((failed + 1))
        rm -rf "$tmp_dir"
        continue
    fi

    mkdir -p "$vol_dir"
    i=1
    for img in "${images[@]}"; do
        img_ext="${img##*.}"
        printf -v num '%04d' "$i"
        cp "$img" "${vol_dir}/${num}.${img_ext}"
        i=$((i + 1))
    done

    echo "  OK: ${vol_dir}/ ($(( i - 1 )) images)"
    succeeded=$((succeeded + 1))
    rm -rf "$tmp_dir"
done

echo ""
echo "=== Done ==="
echo "Extracted: $succeeded  Skipped: $skipped  Failed: $failed"
