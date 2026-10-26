#!/usr/bin/env bash
# Build SDL3 (the ps5 branch in SDL/) as a static library for the PS5 and
# install it into $PS5_PREFIX. The title links $PS5_BUILD/sdl3/libSDL3.a.

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"

bash "$(dirname -- "${BASH_SOURCE[0]}")/sync-src.sh" SDL >/dev/null

B=$PS5_BUILD/sdl3
if [ ! -f "$B/build.ninja" ]; then
    mkdir -p "$B"
    cmake -S "$PS5_SRC/SDL" -B "$B" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$PS5_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="-fno-omit-frame-pointer" \
        -DCMAKE_INSTALL_PREFIX="$PS5_PREFIX" \
        -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_UNIX_CONSOLE_BUILD=ON \
        -DSDL_X11=OFF -DSDL_WAYLAND=OFF -DSDL_KMSDRM=OFF -DSDL_OFFSCREEN=OFF \
        -DSDL_OPENGL=OFF -DSDL_OPENGLES=OFF -DSDL_VULKAN=ON -DSDL_RENDER=OFF -DSDL_GPU=OFF \
        -DSDL_CAMERA=OFF -DSDL_HIDAPI=OFF -DSDL_SENSOR=OFF -DSDL_DIALOG=OFF -DSDL_TRAY=OFF \
        -DSDL_OSS=OFF -DSDL_ALSA=OFF -DSDL_PULSEAUDIO=OFF -DSDL_PIPEWIRE=OFF -DSDL_SNDIO=OFF \
        -DSDL_JACK=OFF -DSDL_DISKAUDIO=OFF -DSDL_DBUS=OFF -DSDL_IBUS=OFF -DSDL_LIBUDEV=OFF \
        -DSDL_LIBICONV=OFF -DSDL_SYSTEM_ICONV=OFF -DSDL_LIBURING=OFF \
        -DSDL_TEST_LIBRARY=OFF -DSDL_EXAMPLES=OFF -DSDL_TESTS=OFF -DSDL_INSTALL=ON \
        -DSDL_CCACHE=OFF > "$B.configure.log" 2>&1 || { cat "$B.configure.log" >&2; exit 1; }
fi
ninja -C "$B"
cmake --install "$B" > /dev/null
grep -E "Video drivers|Audio drivers|Joystick drivers" "$B.configure.log" || true
echo "SDL3: $B/libSDL3.a (installed in $PS5_PREFIX)"
