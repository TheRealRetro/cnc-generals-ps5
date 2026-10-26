#!/usr/bin/env bash
# Assemble the C&C Generals title folder (code from build-generals.sh, game data
# from your own retail copy, fonts) and pack it as a .ffpkg.
#
# Usage: package-generals.sh [game_data_dir]
#   game_data_dir defaults to $PS5_GENERALS_WS/gamedata/generals
#   (see extract-generals-data.sh).
#
# The image contains EA's game files: it is for your own console only.

set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
. "$here/env.sh"
project=$(dirname "$here")

DATA=${1:-$PS5_GENERALS_WS/gamedata/generals}
APP=$PS5_GENERALS_WS/dist/PPSA99203
[ -f "$APP/eboot.bin" ] || { echo "error: $APP/eboot.bin missing (run build-generals.sh)" >&2; exit 1; }
[ -f "$DATA/INI.big" ] || { echo "error: no game data in $DATA (run extract-generals-data.sh)" >&2; exit 1; }

# Game data: the archives and the loose Data/ tree. Not the Windows executables,
# DLLs, Miles plugins or copy-protection files.
rm -rf "$APP/Data" "$APP"/*.big "$APP/fonts"
for big in "$DATA"/*.big; do
    cp -- "$big" "$APP/"
done
cp -r -- "$DATA/Data" "$APP/Data"

# Fonts for FreeType: Liberation (SIL Open Font License 1.1) stands in for Arial,
# Tahoma, Times New Roman and Courier New, and Liberation Sans Narrow for the
# condensed Placard MT. GeneralsX looks in fonts/ (/app0/fonts).
# Needs: apt install fonts-liberation fonts-liberation-sans-narrow
mkdir -p "$APP/fonts"
for font in LiberationSans-Regular LiberationSans-Bold LiberationSerif-Regular LiberationSerif-Bold \
            LiberationMono-Regular LiberationMono-Bold LiberationSansNarrow-Regular LiberationSansNarrow-Bold; do
    cp "/usr/share/fonts/truetype/liberation/$font.ttf" "$APP/fonts/"
done
cp /usr/share/doc/fonts-liberation/copyright "$APP/fonts/LICENSE-Liberation.txt"
cp /usr/share/doc/fonts-liberation-sans-narrow/copyright "$APP/fonts/LICENSE-Liberation-Sans-Narrow.txt"

du -sh "$APP"
mkdir -p "$PS5_GENERALS_WS/out" "$project/out"
bash "$here/mkffpkg.sh" "$APP" "$PS5_GENERALS_WS/out/PPSA99203.ffpkg" | tail -2
cp "$PS5_GENERALS_WS/out/PPSA99203.ffpkg" "$project/out/PPSA99203-generals.ffpkg"
# The linked ELF of this eboot, for scripts/symbolize-crash.sh.
cp "$PS5_BUILD/generals/Generals/ps5-link/link/llvm-pie.elf" "$PS5_GENERALS_WS/out/PPSA99203-generals.elf"
echo "out/PPSA99203-generals.ffpkg (contains your game data: personal use only)"
