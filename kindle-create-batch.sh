#!/usr/bin/env bash
#
# Batch automate Kindle Create to convert manga/comic images into KPF files.
#
# Prerequisites:
#   - Kindle Create open on the content type screen (COMICS selected)
#   - cliclick installed: brew install cliclick
#   - Accessibility permissions for terminal app
#
# Usage:
#   ./kindle-create-batch.sh <images_dir> <output_dir> [author] [publisher]
#
set -euo pipefail

die() { printf 'Error: %s\n' "$1" >&2; exit 1; }

[[ $# -ge 2 ]] || die "Usage: $0 <images_dir> <output_dir> [author] [publisher]"

IMAGES_DIR="$1"
OUTPUT_DIR="$2"
AUTHOR="${3:-}"
PUBLISHER="${4:-}"

[[ -d "$IMAGES_DIR" ]] || die "Images directory not found: $IMAGES_DIR"
command -v cliclick &>/dev/null || die "cliclick not found. Install: brew install cliclick"
mkdir -p "$OUTPUT_DIR"

# ── Window position (top-left corner) ────────────────────────────────────
WIN_X=0
WIN_Y=25

# ── Coordinates (calibrated with window at 0,25 on 2560x1440 display) ───
# Book details fields
FIELD_TITLE_X=460;  FIELD_TITLE_Y=230
FIELD_AUTHOR_X=460; FIELD_AUTHOR_Y=290
FIELD_PUB_X=460;    FIELD_PUB_Y=350

# Properties radio buttons (positions AFTER Virtual Panels is selected,
# which causes "Virtual Panel Movement" to appear and shift items down)
PROP_VPANEL_X=487;  PROP_VPANEL_Y=274   # before shift
PROP_RTL_X=487;     PROP_RTL_Y=385      # after VP Movement shift
PROP_FACING_X=487;  PROP_FACING_Y=447   # after VP Movement shift

# ── Helpers ──────────────────────────────────────────────────────────────

reposition_window() {
    osascript -e "
tell application \"Kindle Create\" to activate
delay 0.5
tell application \"System Events\"
    tell process \"Kindle Create\"
        set position of window 1 to {$WIN_X, $WIN_Y}
        set frontmost to true
    end tell
end tell
"
    sleep 0.5
}

click_field_and_type() {
    local x="$1" y="$2" text="$3"
    cliclick c:"$x","$y"
    sleep 0.2
    osascript -e 'tell application "System Events" to keystroke "a" using command down'
    sleep 0.1
    osascript -e 'tell application "System Events" to key code 51'
    sleep 0.1
    cliclick t:"$text"
    sleep 0.2
}

click_button() {
    osascript -e "
tell application \"System Events\"
    tell process \"Kindle Create\"
        click button \"$1\" of window 1
    end tell
end tell
"
}

# ── Process one volume ───────────────────────────────────────────────────

process_volume() {
    local vol_name="$1"
    local images_dir="$2"
    local output_dir="$3"

    # Reposition window before each volume
    reposition_window

    echo "  [1/8] Continue (content type)..."
    click_button "Continue"
    sleep 2

    echo "  [2/8] Book details..."
    osascript -e 'tell application "Kindle Create" to activate'
    sleep 0.2
    click_field_and_type $FIELD_TITLE_X $FIELD_TITLE_Y "$vol_name"
    if [[ -n "$AUTHOR" ]]; then
        click_field_and_type $FIELD_AUTHOR_X $FIELD_AUTHOR_Y "$AUTHOR"
    fi
    if [[ -n "$PUBLISHER" ]]; then
        click_field_and_type $FIELD_PUB_X $FIELD_PUB_Y "$PUBLISHER"
    fi
    click_button "Continue"
    sleep 2

    echo "  [3/8] Properties (Virtual Panel, RTL, Facing Pages)..."
    osascript -e 'tell application "Kindle Create" to activate'
    sleep 0.2
    cliclick c:$PROP_VPANEL_X,$PROP_VPANEL_Y   # Virtual Panels
    sleep 0.8                                    # wait for VP Movement to appear
    cliclick c:$PROP_RTL_X,$PROP_RTL_Y          # Right-to-Left
    sleep 0.3
    cliclick c:$PROP_FACING_X,$PROP_FACING_Y    # Facing Pages
    sleep 0.3

    echo "  [4/8] Choose Files..."
    osascript << 'SCRIPT'
tell application "System Events"
    tell process "Kindle Create"
        set allButtons to every button of window 1
        repeat with btn in allButtons
            try
                if name of btn contains "Choose" then
                    click btn
                    exit repeat
                end if
            end try
        end repeat
    end tell
end tell
SCRIPT
    sleep 2

    echo "  [5/8] Navigate to images folder..."
    osascript << SCRIPT
tell application "System Events"
    tell process "Kindle Create"
        tell window "Import from file"
            set value of text field 1 to "$images_dir"
            delay 0.3
        end tell
    end tell
end tell
SCRIPT
    sleep 0.3
    osascript -e 'tell application "System Events" to keystroke return'
    sleep 3

    echo "  [5/8] Sort ascending and select all..."
    local dlg_x dlg_y
    dlg_x=$(osascript -e 'tell application "System Events" to tell process "Kindle Create" to tell window "Import from file" to return item 1 of position as integer')
    dlg_y=$(osascript -e 'tell application "System Events" to tell process "Kindle Create" to tell window "Import from file" to return item 2 of position as integer')

    # Click first file to check sort order
    cliclick c:"$((dlg_x + 257))","$((dlg_y + 119))"
    sleep 0.3
    local first_file
    first_file=$(osascript << 'ASCRIPT'
tell application "System Events"
    tell process "Kindle Create"
        tell window "Import from file"
            return value of text field 1
        end tell
    end tell
end tell
ASCRIPT
    ) || first_file=""

    # If first file is NOT 0001, sort is wrong — click Name header to toggle
    if [[ "$first_file" != "0001.png" ]]; then
        echo "    Sort is descending (first=$first_file), clicking Name header..."
        cliclick c:"$((dlg_x + 162))","$((dlg_y + 96))"
        sleep 0.5
    fi

    # Click first file and Cmd+A to select all in ascending order
    cliclick c:"$((dlg_x + 257))","$((dlg_y + 119))"
    sleep 0.2
    osascript -e 'tell application "System Events" to keystroke "a" using command down'
    sleep 0.3

    # Click Open
    osascript << 'SCRIPT'
tell application "System Events"
    tell process "Kindle Create"
        tell window "Import from file"
            click button "Open" of group 1
        end tell
    end tell
end tell
SCRIPT
    sleep 3

    echo "  [6/8] Waiting for import..."
    local waited=0
    while [ $waited -lt 300 ]; do
        sleep 5
        waited=$((waited + 5))
        local result
        result=$(osascript << 'ASCRIPT'
tell application "System Events"
    tell process "Kindle Create"
        try
            set btnNames to name of every button of window 1
            if btnNames contains "Continue" then return "continue"
        end try
        return "importing"
    end tell
end tell
ASCRIPT
        ) || result="importing"
        if [ "$result" != "importing" ]; then
            echo "    Import complete (${waited}s)"
            break
        fi
        printf "    ... %ds\r" "$waited"
    done

    # Click Continue on tutorial overlay
    click_button "Continue"
    sleep 1

    echo "  [7/8] Exporting KPF..."
    osascript << 'SCRIPT'
tell application "System Events"
    tell process "Kindle Create"
        set frontmost to true
        delay 0.3
        keystroke "p" using {command down, shift down}
    end tell
end tell
SCRIPT
    sleep 2

    # Set output path in save dialog and click Save
    osascript << SCRIPT
tell application "System Events"
    tell process "Kindle Create"
        tell window "Save file for Publication"
            set value of text field 1 to "${output_dir}/${vol_name}"
            delay 0.3
            click button "Save" of group 1
        end tell
    end tell
end tell
SCRIPT
    sleep 2

    # Wait for export
    local kpf="${output_dir}/${vol_name}.kpf"
    waited=0
    while [ $waited -lt 600 ]; do
        sleep 5
        waited=$((waited + 5))
        if [ -f "$kpf" ]; then
            local size1 size2
            size1=$(stat -f %z "$kpf" 2>/dev/null || echo "0")
            sleep 2
            size2=$(stat -f %z "$kpf" 2>/dev/null || echo "0")
            if [ "$size1" = "$size2" ] && [ "$size1" != "0" ]; then
                echo "    Export complete (${waited}s, $(du -h "$kpf" | cut -f1))"
                break
            fi
        fi
        printf "    ... exporting %ds\r" "$waited"
    done

    echo "  [8/8] Closing project..."
    # Dismiss "ready to publish" popup
    sleep 2
    osascript << 'SCRIPT'
tell application "System Events"
    tell process "Kindle Create"
        try
            click button "OK" of window 1
        end try
    end tell
end tell
SCRIPT
    sleep 1

    # File → New Project
    osascript << 'SCRIPT'
tell application "System Events"
    tell process "Kindle Create"
        click menu item "New Project" of menu "File" of menu bar 1
    end tell
end tell
SCRIPT
    sleep 1

    # Don't Save dialog
    osascript << 'SCRIPT'
tell application "System Events"
    tell process "Kindle Create"
        try
            click button "Don't Save" of sheet 1 of window 1
        end try
        try
            click button "Don't Save" of window 1
        end try
    end tell
end tell
SCRIPT
    sleep 2
}

# ── Main loop ────────────────────────────────────────────────────────────

mapfile -t VOLUMES < <(ls -d "$IMAGES_DIR"/*/ 2>/dev/null | sort)
TOTAL=${#VOLUMES[@]}
[[ $TOTAL -gt 0 ]] || die "No volume folders found in $IMAGES_DIR"

echo "=== Kindle Create Batch Automation ==="
echo "Volumes: $TOTAL | Output: $OUTPUT_DIR"
echo ""

succeeded=0
failed=0
skipped=0

for vol_path in "${VOLUMES[@]}"; do
    vol_name=$(basename "$vol_path")
    kpf="${OUTPUT_DIR}/${vol_name}.kpf"
    idx=$((succeeded + failed + skipped + 1))

    echo "=== [$idx/$TOTAL] $vol_name ==="

    if [[ -f "$kpf" ]]; then
        echo "  SKIP: KPF already exists"
        skipped=$((skipped + 1))
        continue
    fi

    if process_volume "$vol_name" "$vol_path" "$OUTPUT_DIR"; then
        if [[ -f "$kpf" ]]; then
            succeeded=$((succeeded + 1))
        else
            echo "  FAIL: KPF not created"
            failed=$((failed + 1))
        fi
    else
        echo "  FAIL: Process error"
        failed=$((failed + 1))
    fi
    echo ""
done

echo "=== Done ==="
echo "Succeeded: $succeeded  Skipped: $skipped  Failed: $failed"
[[ $failed -eq 0 ]] || exit 1
