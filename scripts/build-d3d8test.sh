#!/usr/bin/env bash
# Build the D3D8 smoke test title (PPSA99204) and pack it as a .ffpkg.
# Needs build-sdl3.sh and build-dxvk.sh first.

set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
. "$here/env.sh"
project=$(dirname "$here")

B=$PS5_BUILD/d3d8test
mkdir -p "$B/obj" "$B/sce_sys"
SDL=$PS5_SRC/SDL
DXVK=$PS5_SRC/dxvk
defs=(-DNDEBUG -O2 -g1 -fno-omit-frame-pointer -ffunction-sections -fdata-sections)

"$PS5_SDK/bin/prospero-clang" -std=c11 "${defs[@]}" -c "$project/ps5/runtime/ps5_title.c" -o "$B/obj/ps5_title.o"
"$PS5_SDK/bin/prospero-clang++" -std=c++17 "${defs[@]}" \
    -I"$SDL/include" -I"$DXVK/include/native/directx" -I"$DXVK/include/native/windows" -I"$project/ps5/runtime" \
    -c "$project/ps5/d3d8test/main.cpp" -o "$B/obj/main.o"

cp "$project/ps5/d3d8test/sce_sys/param.json" "$B/sce_sys/"
[ -f "$B/sce_sys/icon0.png" ] || python3 "$here/make-icon.py" "$B/sce_sys/icon0.png" GENERALS D3D8 TEST

APP=$PS5_GENERALS_WS/dist/PPSA99204
rm -rf "$APP"
bash "$project/ps5/tools/link-title.sh" "$B" "$B/sce_sys" "$APP" \
    "$B/obj/main.o" "$B/obj/ps5_title.o" \
    "$PS5_BUILD/dxvk/libdxvk_ps5.a" "$PS5_BUILD/sdl3/libSDL3.a"

mkdir -p "$PS5_GENERALS_WS/out" "$project/out"
bash "$here/mkffpkg.sh" "$APP" "$PS5_GENERALS_WS/out/PPSA99204.ffpkg" | tail -1
cp "$PS5_GENERALS_WS/out/PPSA99204.ffpkg" "$project/out/PPSA99204-d3d8-test.ffpkg"
echo "out/PPSA99204-d3d8-test.ffpkg"
