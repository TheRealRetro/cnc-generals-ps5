#!/usr/bin/env bash
# Build C&C Generals (GeneralsX, the ps5 branch in GeneralsX/) for the PS5 into
# the title folder $PS5_GENERALS_WS/dist/PPSA99203 (code only; see
# package-generals.sh for the game data and the .ffpkg).
# Needs build-sdl3.sh, build-deps.sh, build-ffmpeg.sh and build-dxvk.sh first.
#
# Usage: build-generals.sh [ninja args...]   (e.g. -k 0 to see every error)

set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
. "$here/env.sh"
project=$(dirname "$here")

bash "$here/sync-src.sh" GeneralsX ps5 scripts >/dev/null

B=$PS5_BUILD/generals
mkdir -p "$B/sce_sys"
cp "$project/ps5/generals/sce_sys/param.json" "$B/sce_sys/"
[ -f "$B/sce_sys/icon0.png" ] || python3 "$here/make-icon.py" "$B/sce_sys/icon0.png" "C&C" GENERALS

if [ ! -f "$B/build.ninja" ] || [ ! -f "$B/CMakeCache.txt" ]; then
    cmake -S "$PS5_SRC/GeneralsX" -B "$B" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$PS5_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_FIND_ROOT_PATH="$PS5_PREFIX" -DCMAKE_PREFIX_PATH=/ \
        -DCMAKE_C_FLAGS="-fno-omit-frame-pointer" -DCMAKE_CXX_FLAGS="-fno-omit-frame-pointer" \
        -DCMAKE_CXX_SCAN_FOR_MODULES=OFF \
        -DRTS_BUILD_ZEROHOUR=OFF -DRTS_BUILD_GENERALS=ON \
        -DRTS_BUILD_CORE_TOOLS=OFF -DRTS_BUILD_CORE_EXTRAS=OFF \
        -DRTS_BUILD_GENERALS_TOOLS=OFF -DRTS_BUILD_GENERALS_EXTRAS=OFF \
        -DRTS_BUILD_OPTION_SAGE_PATCH=OFF -DRTS_BUILD_OPTION_FFMPEG=ON \
        -DRTS_CRASHDUMP_ENABLE=OFF -DRTS_BUILD_OPTION_DEEP_CRC=OFF \
        -DSAGE_USE_DX8=OFF -DSAGE_USE_SDL3=ON -DSAGE_USE_OPENAL=OFF -DSAGE_USE_MINIAUDIO=ON \
        -DSAGE_USE_GLM=ON -DSAGE_UPDATE_CHECK=OFF -DSAGE_USE_NGMP=OFF \
        -DSAGE_PS5_DIR="$PS5_SRC/ps5" -DSAGE_PS5_DXVK_DIR="$PS5_SRC/dxvk" \
        -DSAGE_PS5_DXVK_LIB="$PS5_BUILD/dxvk/libdxvk_ps5.a" \
        -DSAGE_PS5_SCE_SYS="$B/sce_sys" -DSAGE_PS5_DIST="$PS5_GENERALS_WS/dist/PPSA99203" \
        > "$B.configure.log" 2>&1 || { tail -40 "$B.configure.log" >&2; exit 1; }
fi
ninja -C "$B" "$@" g_generals
