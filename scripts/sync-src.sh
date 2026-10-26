#!/usr/bin/env bash
# Mirror the source checkouts from the Windows project folder into the WSL
# build workspace. The Windows path has spaces and '&', which meson and some
# Makefiles mishandle, and builds on /mnt/c are slow; builds read the mirror.
#
# Usage: sync-src.sh [name...]   (default: GeneralsX SDL dxvk ps5 scripts)
# ps5/ and scripts/ go along because builds call the link scripts from the mirror.

set -euo pipefail

PROJECT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DEST=${PS5_GENERALS_WS:-/root/ps5-generals}/src

names=("$@")
[ ${#names[@]} -gt 0 ] || names=(GeneralsX SDL dxvk ps5 scripts)

mkdir -p -- "$DEST"
for name in "${names[@]}"; do
    [ -d "$PROJECT/$name" ] || { echo "error: $PROJECT/$name not found" >&2; exit 1; }
    # .git stays behind; dxvk's submodules are plain directories after the copy.
    rsync -a --delete --exclude=.git --exclude=/build/ "$PROJECT/$name/" "$DEST/$name/"
    echo "synced $name -> $DEST/$name"
done
