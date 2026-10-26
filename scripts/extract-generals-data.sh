#!/usr/bin/env bash
# Rebuild the installed C&C Generals game folder from copies of the retail discs,
# without running the Windows installer (no SafeDisc, no registry).
#
# Usage: extract-generals-data.sh <disc_root> <output_dir>
#   <disc_root> contains "Disk 1" and "Disk 2" copied from the retail CDs.
#   <output_dir> receives the game folder (the .big archives, Data/, Maps/, ...).
#
# Requires: msitools (msiextract)

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: $0 <disc_root> <output_dir>" >&2
    exit 1
fi

DISC_ROOT=$(realpath -- "$1")
OUT=$(realpath -m -- "$2")
MSI_NAME="Command & Conquer Generals.msi"

command -v msiextract >/dev/null || { echo "error: msiextract not installed (apt install msitools)" >&2; exit 1; }
[ -f "$DISC_ROOT/Disk 1/$MSI_NAME" ] || { echo "error: '$DISC_ROOT/Disk 1/$MSI_NAME' not found" >&2; exit 1; }
[ -f "$DISC_ROOT/Disk 2/Data2.cab" ] || { echo "error: '$DISC_ROOT/Disk 2/Data2.cab' not found" >&2; exit 1; }

# msiextract looks for the external cabinets next to the .msi, but Data2.cab is
# on the second disc, so gather both discs into one directory of symlinks.
STAGE=$(mktemp -d)
RAW=$(mktemp -d)
trap 'rm -rf -- "$STAGE" "$RAW"' EXIT
for f in "$DISC_ROOT/Disk 1/"* "$DISC_ROOT/Disk 2/"*; do
    [ -f "$f" ] && ln -sf -- "$f" "$STAGE/"
done

echo "Extracting installer contents..."
(cd "$RAW" && msiextract --directory "$RAW" "$STAGE/$MSI_NAME" >/dev/null)

# The game lives under Program Files/EA Games/Command and Conquer Generals.
GAME_DIR=$(find "$RAW" -type f -iname 'INI.big' -printf '%h\n' | head -1)
[ -n "$GAME_DIR" ] || { echo "error: INI.big not found in extracted installer" >&2; exit 1; }

mkdir -p -- "$OUT"
cp -a -- "$GAME_DIR/." "$OUT/"

echo "Game folder: $OUT"
find "$OUT" -maxdepth 1 -type f -iname '*.big' -printf '%10s  %f\n' | sort -k2
find "$OUT" -type f -printf '%s\n' | awk '{s += $1; n++} END {printf "%d files, %.2f GB\n", n, s / 1073741824}'
