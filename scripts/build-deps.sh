#!/usr/bin/env bash
# Third-party libraries GeneralsX needs, built for the PS5 into $PS5_PREFIX:
#   GLM 1.0.1 and gli (headers, with CMake package files GeneralsX finds),
#   FreeType 2.13.3 (text rendering; no optional codecs),
#   SDL3_image 3.4.0 (cursor .ani/.ico loading; stb backend, no external libs).
# Needs build-sdl3.sh first (SDL3_image builds against the installed SDL3).

set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"

TP=$PS5_SRC/thirdparty
mkdir -p "$TP" "$PS5_PREFIX/include" "$PS5_PREFIX/lib/cmake"
cmake_ps5=(-G Ninja -DCMAKE_TOOLCHAIN_FILE="$PS5_TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX="$PS5_PREFIX" -DCMAKE_FIND_ROOT_PATH="$PS5_PREFIX" -DCMAKE_PREFIX_PATH=/
    -DBUILD_SHARED_LIBS=OFF -DCMAKE_C_FLAGS=-fno-omit-frame-pointer -DCMAKE_CXX_FLAGS=-fno-omit-frame-pointer)

fetch() { # fetch <dir> <git url> <ref>
    [ -d "$TP/$1" ] || git -c advice.detachedHead=false clone -q --depth 1 --branch "$3" "$2" "$TP/$1"
}

# --- GLM (header-only) ---
fetch glm https://github.com/g-truc/glm.git 1.0.1
rm -rf "$PS5_PREFIX/include/glm" && cp -r "$TP/glm/glm" "$PS5_PREFIX/include/glm"
find "$PS5_PREFIX/include/glm" -name '*.cpp' -o -name 'CMakeLists.txt' | xargs -r rm -f
mkdir -p "$PS5_PREFIX/lib/cmake/glm"
cat > "$PS5_PREFIX/lib/cmake/glm/glmConfig.cmake" <<'EOF'
# GLM 1.0.1, header-only, for the PS5 build.
if(NOT TARGET glm::glm)
    add_library(glm::glm INTERFACE IMPORTED)
    set_target_properties(glm::glm PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_LIST_DIR}/../../../include")
endif()
EOF

# --- gli (header-only, needs GLM) ---
fetch gli https://github.com/g-truc/gli.git master
rm -rf "$PS5_PREFIX/include/gli" && cp -r "$TP/gli/gli" "$PS5_PREFIX/include/gli"
mkdir -p "$PS5_PREFIX/lib/cmake/gli"
cat > "$PS5_PREFIX/lib/cmake/gli/gliConfig.cmake" <<'EOF'
# gli, header-only, for the PS5 build (target name as vcpkg's port: gli).
include(CMakeFindDependencyMacro)
find_dependency(glm CONFIG)
if(NOT TARGET gli)
    add_library(gli INTERFACE IMPORTED)
    set_target_properties(gli PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_LIST_DIR}/../../../include"
        INTERFACE_LINK_LIBRARIES glm::glm)
endif()
EOF

# --- FreeType ---
fetch freetype https://github.com/freetype/freetype.git VER-2-13-3
B=$PS5_BUILD/freetype
if [ ! -f "$PS5_PREFIX/lib/libfreetype.a" ]; then
    cmake -S "$TP/freetype" -B "$B" "${cmake_ps5[@]}" \
        -DFT_DISABLE_ZLIB=ON -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_PNG=ON \
        -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON > "$B.configure.log" 2>&1 ||
        { cat "$B.configure.log" >&2; exit 1; }
    ninja -C "$B" install > /dev/null
fi

# --- SDL3_image ---
fetch SDL_image https://github.com/libsdl-org/SDL_image.git release-3.4.0
B=$PS5_BUILD/sdl3_image
if [ ! -f "$PS5_PREFIX/lib/libSDL3_image.a" ]; then
    cmake -S "$TP/SDL_image" -B "$B" "${cmake_ps5[@]}" \
        -DSDLIMAGE_VENDORED=OFF -DSDLIMAGE_DEPS_SHARED=OFF -DSDLIMAGE_BACKEND_STB=ON \
        -DSDLIMAGE_PNG=ON -DSDLIMAGE_JPG=ON -DSDLIMAGE_AVIF=OFF -DSDLIMAGE_JXL=OFF \
        -DSDLIMAGE_TIF=OFF -DSDLIMAGE_WEBP=OFF -DSDLIMAGE_SAMPLES=OFF -DSDLIMAGE_TESTS=OFF \
        > "$B.configure.log" 2>&1 || { cat "$B.configure.log" >&2; exit 1; }
    ninja -C "$B" install > /dev/null
fi

ls -la "$PS5_PREFIX/lib" "$PS5_PREFIX/lib/cmake"
