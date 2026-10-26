# Shared paths for the PS5 build scripts. Source it: . scripts/env.sh

PS5_GENERALS_WS=${PS5_GENERALS_WS:-/root/ps5-generals}
PS5_DEPS=$PS5_GENERALS_WS/deps
# The payload SDK titles build with: PS5_VulkanTemplate's pin of the PS5_PayloadSDK
# fork (platform layer included). RADV, its link recipe, the native tool and
# libc.prx come from PS5_Vulkan.
PS5_SDK=${PS5_SDK:-$PS5_DEPS/PS5_VulkanTemplate/.deps/native/ps5-payload-sdk}
PS5_VULKAN_DIR=${PS5_VULKAN_DIR:-$PS5_DEPS/PS5_Vulkan}
PS5_SRC=$PS5_GENERALS_WS/src
PS5_BUILD=$PS5_GENERALS_WS/build
PS5_TOOLCHAIN=$PS5_SDK/toolchain/prospero.cmake
# Third-party libraries built for the console (SDL3, SDL3_image, FreeType, GLM, gli).
# The SDK toolchain only searches its sysroot, so CMake builds add this prefix
# to CMAKE_FIND_ROOT_PATH.
PS5_PREFIX=$PS5_GENERALS_WS/prefix

export PATH=$HOME/.local/bin:$PATH
export PS5_CLANG=${PS5_CLANG:-$(command -v clang || true)}
