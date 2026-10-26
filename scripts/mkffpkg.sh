#!/usr/bin/env bash
# Build a ShadowMountPlus .ffpkg (UFS2) image from a PS5 title folder on Linux/WSL.
#
# Linux port of ShadowMountPlus mkufs2.sh: same UFS2 profile (-b 65536 -f 65536
# -S 4096 -m 0), same sizing and inode-density rules, but uses makefs instead of
# mdconfig/newfs/mount, so no root mount or FreeBSD host is needed: the makefs
# scripts/build-makefs.sh builds, which lays UFS2 out as FreeBSD's newfs does
# (Ubuntu's own puts the superblock where the console's kernel does not look).
# check-ufs2.py then reads the image back as the kernel will.
#
# Usage: mkffpkg.sh <title_dir> [output.ffpkg]

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <title_dir> [output.ffpkg]" >&2
    exit 1
fi

INPUT_DIR=$(realpath -- "$1")
OUTPUT=${2:-$(basename -- "$INPUT_DIR").ffpkg}

[ -d "$INPUT_DIR" ] || { echo "error: input directory not found: $INPUT_DIR" >&2; exit 1; }
[ -f "$INPUT_DIR/eboot.bin" ] || { echo "error: eboot.bin not found in $INPUT_DIR" >&2; exit 1; }
[ -f "$INPUT_DIR/sce_sys/param.json" ] || { echo "error: sce_sys/param.json not found in $INPUT_DIR" >&2; exit 1; }
MAKEFS=${MAKEFS:-${PS5_GENERALS_WS:-/root/ps5-generals}/toolchains/makefs/makefs}
[ -x "$MAKEFS" ] || { echo "error: $MAKEFS not found (run scripts/build-makefs.sh)" >&2; exit 1; }

BLOCK_SIZE=65536
FRAG_SIZE=65536
SECTOR_SIZE=4096
MINFREE_PERCENT=0
DEFAULT_BYTES_PER_INODE=$((4 * FRAG_SIZE))
MIN_BYTES_PER_INODE=$FRAG_SIZE
INODE_SIZE=256
INODE_SPARE=2048
META_FIXED=$((64 * 1024 * 1024))
MIN_SLACK=$((64 * 1024 * 1024))
SPARE_MIN=$((64 * 1024 * 1024))
SPARE_MAX=$((512 * 1024 * 1024))

FILE_COUNT=$(find "$INPUT_DIR" -type f | wc -l)
DIR_COUNT=$(find "$INPUT_DIR" -type d | wc -l)
RAW_FILE_BYTES=$(find "$INPUT_DIR" -type f -printf '%s\n' | awk '{s += $1} END {printf "%d", s}')
DATA_BYTES=$(find "$INPUT_DIR" -type f -printf '%s\n' |
    awk -v frag="$FRAG_SIZE" '{s += int(($1 + frag - 1) / frag) * frag} END {printf "%d", s}')
DIR_BYTES=$((DIR_COUNT * FRAG_SIZE))
INODE_COUNT=$((FILE_COUNT + DIR_COUNT + INODE_SPARE))
INODE_BYTES=$((INODE_COUNT * INODE_SIZE))

BASE_TOTAL=$((DATA_BYTES + DIR_BYTES + INODE_BYTES + META_FIXED))
SPARE_BYTES=$((BASE_TOTAL / 200))
[ "$SPARE_BYTES" -lt "$SPARE_MIN" ] && SPARE_BYTES=$SPARE_MIN
[ "$SPARE_BYTES" -gt "$SPARE_MAX" ] && SPARE_BYTES=$SPARE_MAX
TOTAL=$((BASE_TOTAL + SPARE_BYTES))
MIN_TOTAL=$((RAW_FILE_BYTES + MIN_SLACK))
[ "$TOTAL" -lt "$MIN_TOTAL" ] && TOTAL=$MIN_TOTAL

MB=$(((TOTAL + 1024 * 1024 - 1) / (1024 * 1024)))
IMAGE_BYTES=$((MB * 1024 * 1024))

BYTES_PER_INODE=$DEFAULT_BYTES_PER_INODE
AUTO_BYTES_PER_INODE=$((IMAGE_BYTES / INODE_COUNT))
AUTO_BYTES_PER_INODE=$(((AUTO_BYTES_PER_INODE / SECTOR_SIZE) * SECTOR_SIZE))
[ "$AUTO_BYTES_PER_INODE" -lt "$MIN_BYTES_PER_INODE" ] && AUTO_BYTES_PER_INODE=$MIN_BYTES_PER_INODE
[ "$AUTO_BYTES_PER_INODE" -lt "$BYTES_PER_INODE" ] && BYTES_PER_INODE=$AUTO_BYTES_PER_INODE

echo "Input:        $INPUT_DIR"
echo "Files: $FILE_COUNT, Dirs: $DIR_COUNT, raw bytes: $RAW_FILE_BYTES"
echo "UFS2 profile: -b $BLOCK_SIZE -f $FRAG_SIZE -m $MINFREE_PERCENT -S $SECTOR_SIZE -i $BYTES_PER_INODE"
echo "Image size:   ${MB}MB"

# mkufs2.sh copies with tar and then chmod -R 777 on the contents; makefs takes
# modes from the source tree, so stage a 0777 copy (hard links would chmod the
# originals). Keep the staging directory on the same filesystem as the output.
STAGE=$(mktemp -d "$(dirname -- "$(realpath -m -- "$OUTPUT")")/.ffpkg-stage.XXXXXX")
trap 'rm -rf -- "$STAGE"' EXIT
cp -a -- "$INPUT_DIR/." "$STAGE/"
chmod -R 777 -- "$STAGE"
chmod 755 -- "$STAGE"
chown -R 0:0 -- "$STAGE" 2>/dev/null || true

rm -f -- "$OUTPUT"
# -S 512, not 4096: FreeBSD's newfs turns -S 4096 back into 512-byte units
# (DEV_BSIZE) before it lays out the file system, and the kernel reads blocks at
# fsbtodb() addresses in those units. makefs does not, and with -S 4096 its
# fs_fsbtodb (and di_blocks) are 8 times too small for the console's kernel.
"$MAKEFS" -t ffs -B little -S 512 -s "$IMAGE_BYTES" \
    -o "version=2,bsize=$BLOCK_SIZE,fsize=$FRAG_SIZE,minfree=$MINFREE_PERCENT,density=$BYTES_PER_INODE" \
    "$OUTPUT" "$STAGE"

# Mount-time superblock checks, then every file read back from the root inode
# and compared with the title folder.
python3 -I "$(dirname -- "$(realpath -- "$0")")/check-ufs2.py" "$OUTPUT" "$STAGE"

echo "Created $OUTPUT"
