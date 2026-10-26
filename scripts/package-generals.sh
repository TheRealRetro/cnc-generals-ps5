#!/usr/bin/env bash
# Assemble the C&C Generals title folder (code from build-generals.sh, fonts and,
# unless --without-data, game data from your own retail copy) and pack it as a
# .ffpkg.
#
# Usage: package-generals.sh [game_data_dir]
#          out/PPSA99203-generals.ffpkg, with the game data. game_data_dir
#          defaults to $PS5_GENERALS_WS/gamedata/generals (extract-generals-data.sh).
#          It contains EA's game files: it is for your own console only.
#        package-generals.sh --without-data
#          out/PPSA99203-generals-nodata.ffpkg: the game's code, runtime and
#          fonts only, nothing of EA's, to share. Its players copy their own
#          game files to /data/generals on the console (README.md).

set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
. "$here/env.sh"
project=$(dirname "$here")

WITH_DATA=1
if [ "${1:-}" = --without-data ]; then
    WITH_DATA=0
    shift
fi
DATA=${1:-$PS5_GENERALS_WS/gamedata/generals}
APP=$PS5_GENERALS_WS/dist/PPSA99203
[ -f "$APP/eboot.bin" ] || { echo "error: $APP/eboot.bin missing (run build-generals.sh)" >&2; exit 1; }
if [ "$WITH_DATA" = 1 ]; then
    [ -f "$DATA/INI.big" ] || { echo "error: no game data in $DATA (run extract-generals-data.sh)" >&2; exit 1; }
fi

# Game data: the archives and the loose Data/ tree. Not the Windows executables,
# DLLs, Miles plugins or copy-protection files. Without it, the game looks for
# the player's copy on the console instead (SDL3Main.cpp, FindPS5GameData).
rm -rf "$APP/Data" "$APP"/*.big "$APP/fonts"
if [ "$WITH_DATA" = 1 ]; then
    for big in "$DATA"/*.big; do
        cp -- "$big" "$APP/"
    done
    cp -r -- "$DATA/Data" "$APP/Data"
fi

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

# Licences: the program's (GPL-3.0 and EA's terms), the notice that lists what
# it is built from (ps5/generals/licenses/NOTICE.md), and each component's
# licence text, from the sources the build used. A missing text stops packing.
rm -rf "$APP/licenses"
mkdir -p "$APP/licenses"
deps=$PS5_BUILD/generals/_deps
zlib_src=$PS5_BUILD/generals/Core/Libraries/Source/Compression/_deps/zlib-1.1.4-src/ZLib
cp "$project/LICENSE" "$project/EA-ADDITIONAL-TERMS.md" "$project/ps5/generals/licenses/NOTICE.md" "$APP/licenses/"
while read -r source target; do
    cp "$source" "$APP/licenses/$target"
done <<EOF
$deps/gamespy-src/LICENSE GameSpy-LICENSE
$deps/gamemath-src/LICENSE.md GameMath-LICENSE.md
$deps/miniaudio-src/LICENSE miniaudio-LICENSE
$deps/stb-src/LICENSE stb-LICENSE
$PS5_SRC/SDL/LICENSE.txt SDL-LICENSE.txt
$PS5_SRC/thirdparty/SDL_image/LICENSE.txt SDL_image-LICENSE.txt
$PS5_SRC/thirdparty/freetype/LICENSE.TXT FreeType-LICENSE.TXT
$PS5_SRC/thirdparty/freetype/docs/FTL.TXT FreeType-FTL.TXT
$PS5_SRC/thirdparty/glm/copying.txt GLM-copying.txt
$PS5_SRC/dxvk/LICENSE DXVK-LICENSE
$PS5_SRC/dxvk/subprojects/libdisplay-info/LICENSE libdisplay-info-LICENSE
$PS5_SRC/thirdparty/ffmpeg/COPYING.LGPLv2.1 FFmpeg-COPYING.LGPLv2.1
$PS5_SRC/thirdparty/ffmpeg/LICENSE.md FFmpeg-LICENSE.md
$PS5_DEPS/PS5_Mesa/docs/license.rst Mesa-license.rst
$PS5_DEPS/PS5_Mesa/licenses/MIT Mesa-MIT
EOF
# zlib 1.1.4 and LZH-Light carry their notices in their sources.
sed -n '/Copyright (C) 1995-2002/,/madler@alumni.caltech.edu/p' "$zlib_src/zlib.h" > "$APP/licenses/zlib-1.1.4.txt"
sed -n '2,12p' "$deps/lzhl-src/CompLibHeader/Lzhl.cpp" | sed 's/^ \*\{0,1\} \{0,2\}//' > "$APP/licenses/LZHL.txt"
for text in zlib-1.1.4.txt LZHL.txt; do
    [ -s "$APP/licenses/$text" ] || { echo "error: no licence text for $text" >&2; exit 1; }
done

if [ "$WITH_DATA" = 1 ]; then
    name=PPSA99203-generals
else
    name=PPSA99203-generals-nodata
    # Nothing of EA's may be in it.
    if find "$APP" -iname '*.big' -o -iname '*.bik' -o -iname '*.wnd' -o -iname '*.ani' | grep -q .; then
        echo "error: game files in $APP" >&2
        exit 1
    fi
fi
du -sh "$APP"
mkdir -p "$PS5_GENERALS_WS/out" "$project/out"
bash "$here/mkffpkg.sh" "$APP" "$PS5_GENERALS_WS/out/$name.ffpkg" | tail -2
cp "$PS5_GENERALS_WS/out/$name.ffpkg" "$project/out/$name.ffpkg"
# The linked ELF of this eboot, for scripts/symbolize-crash.sh.
cp "$PS5_BUILD/generals/Generals/ps5-link/link/llvm-pie.elf" "$PS5_GENERALS_WS/out/PPSA99203-generals.elf"
if [ "$WITH_DATA" = 1 ]; then
    echo "out/$name.ffpkg (contains your game data: personal use only)"
else
    echo "out/$name.ffpkg (no game data: players copy theirs to /data/generals)"
fi
