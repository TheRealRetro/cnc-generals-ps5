#!/usr/bin/env bash
# FFmpeg for the PS5, into $PS5_PREFIX: just what the game's Bink videos need.
# GeneralsX plays them with FFmpegVideoPlayer (libavformat's bink demuxer,
# libavcodec's bink and binkaudio decoders, libswscale to convert the frames),
# reading through its own AVIO callbacks, so no protocols or other formats.
#
# FFmpeg 7.1.1, LGPL 2.1+ (no --enable-gpl or nonfree parts), static. No
# x86 assembly (it needs nasm, and Bink's 2003-era video decodes easily in C),
# and no autodetected system libraries: the console has none.

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"

VERSION=n7.1.1
SRC=$PS5_SRC/thirdparty/ffmpeg
BUILD=$PS5_BUILD/ffmpeg

if [ ! -d "$SRC" ]; then
    git -c advice.detachedHead=false clone -q --depth 1 --branch "$VERSION" https://github.com/FFmpeg/FFmpeg.git "$SRC"
fi
echo "FFmpeg $VERSION at $(git -C "$SRC" rev-parse --short=12 HEAD)"

rm -rf "$BUILD"
mkdir -p "$BUILD"
cd "$BUILD"
"$SRC/configure" \
    --prefix="$PS5_PREFIX" \
    --enable-cross-compile --target-os=freebsd --arch=x86_64 \
    --cc="$PS5_SDK/bin/prospero-clang" --cxx="$PS5_SDK/bin/prospero-clang++" \
    --ar="$PS5_SDK/bin/llvm-ar" --ranlib="$PS5_SDK/bin/llvm-ranlib" \
    --nm="$PS5_SDK/bin/llvm-nm" --strip="$PS5_SDK/bin/llvm-strip" \
    --pkg-config=false \
    --extra-cflags="-fno-omit-frame-pointer" \
    --enable-static --disable-shared --enable-pic \
    --disable-autodetect --disable-x86asm \
    --disable-programs --disable-doc --disable-debug --disable-network \
    --disable-avdevice --disable-avfilter --disable-swresample \
    --disable-everything \
    --enable-demuxer=bink \
    --enable-decoder=bink,binkaudio_rdft,binkaudio_dct \
    --enable-avformat --enable-avcodec --enable-swscale > configure.log 2>&1 ||
    { tail -30 configure.log; tail -40 ffbuild/config.log; exit 1; }
grep -E "^(demuxers|decoders|License)|Enabled (demuxers|decoders)" -A2 configure.log | head -12 || true

make -j"$(nproc)" > make.log 2>&1 || { grep -E "error|Error" make.log | head -30; exit 1; }
make install > install.log 2>&1
for lib in avformat avcodec swscale avutil; do
    ls -la "$PS5_PREFIX/lib/lib$lib.a"
done
echo "==> FFmpeg $VERSION in $PS5_PREFIX"
