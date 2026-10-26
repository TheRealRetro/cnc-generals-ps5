#!/usr/bin/env bash
# Build DXVK (the ps5 branch in dxvk/) for the PS5: static D3D8 + D3D9 and
# DXVK's core libraries, SDL3 WSI linked directly. Output in $PS5_BUILD/dxvk.

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"

bash "$(dirname -- "${BASH_SOURCE[0]}")/sync-src.sh" dxvk >/dev/null

B=$PS5_BUILD/dxvk
# The console's FreeBSD 9 <assert.h> has no C11 static_assert macro (used by
# libdisplay-info); C files get the keyword under that name.
if [ ! -f "$B/build.ninja" ]; then
    # meson itself, not prospero-meson: the wrapper re-splits arguments on spaces.
    meson setup --cross-file="$PS5_SDK/toolchain/prospero.ini" "$B" "$PS5_SRC/dxvk" \
        --buildtype=release -Db_ndebug=true \
        -Dc_args="-fno-omit-frame-pointer -Dstatic_assert=_Static_assert" \
        -Dcpp_args=-fno-omit-frame-pointer \
        -Dps5=true -Dps5_sdl3_include="$PS5_SRC/SDL/include" \
        -Denable_dxgi=false -Denable_d3d10=false -Denable_d3d11=false \
        -Denable_d3d9=true -Denable_d3d8=true > "$B.configure.log" 2>&1 ||
        { cat "$B.configure.log" >&2; exit 1; }
fi
ninja -C "$B"

# One regular archive for the title link: meson's internal libraries are thin
# archives that only point at their objects.
OUT=$B/libdxvk_ps5.a
rm -f "$OUT"
{
    echo "create $OUT"
    for lib in src/d3d8/libdxvk_d3d8.a src/d3d9/libdxvk_d3d9.a src/dxso/libdxso.a src/dxvk/libdxvk.a \
               src/spirv/libspirv.a src/util/libutil.a src/vulkan/libvkcommon.a src/wsi/libwsi.a \
               subprojects/libdisplay-info/libdisplay-info.a; do
        echo "addlib $B/$lib"
    done
    echo "save"
    echo "end"
} | "$PS5_SDK/bin/llvm-ar" -M
# Read the listing whole before searching it: under pipefail, grep -q stopping
# at the match makes llvm-nm die of SIGPIPE and the check fail.
grep -q " T Direct3DCreate8$" <<<"$("$PS5_SDK/bin/llvm-nm" --defined-only "$OUT" 2>/dev/null)" ||
    { echo "error: Direct3DCreate8 missing from $OUT" >&2; exit 1; }
ls -la "$OUT"
