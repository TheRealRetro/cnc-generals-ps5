#!/usr/bin/env bash
# Link a PS5 title with RADV and package its folder.
#
#   link-title.sh WORK_DIR SCE_SYS_DIR DIST_DIR INPUT...
#
# INPUT is any mix of object files and static archives (the archives are
# searched as one group). SCE_SYS_DIR holds param.json and the presentation
# files. DIST_DIR becomes the title folder: eboot.bin, sce_sys/, sce_module/.
#
# The link is PS5_Vulkan's recipe (tools/radv-link.sh: RADV archive, platform
# layer, heap and thread wraps, libc names bound to ps5_*), as
# PS5_VulkanTemplate's ps5/tools/link-title.sh uses it, with two changes for an
# Ubuntu host:
#  - the final link runs LLD 21 (LLVM_CONFIG for that step only: the SDK's
#    compiler wrappers change behaviour with LLVM 20+), and
#  - -z nodynamic-undefined-weak: Mesa's dispatch tables reference every entry
#    point weakly; those not defined must resolve to NULL here, not become
#    imports the native tool cannot place.
#
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
[[ -n ${LINK_TRACE:-} ]] && set -x

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
. "$here/../../scripts/env.sh"

work=$1 sce_sys=$2 app=$3
shift 3
inputs=("$@")

vulkan=$PS5_VULKAN_DIR
sdk=$PS5_SDK
archive=${RADV_ARCHIVE:-$vulkan/.deps/native/radv-release/lib/libvulkan_radeon.ps5.a}
tool="$vulkan/build/host/ps5-native-tool"
native="$vulkan/tooling/native"
lld21_config=${PS5_LINK_LLVM_CONFIG:-$PS5_GENERALS_WS/toolchains/llvm-21/bin/llvm-config}

for file in "$archive" "$tool" "$sce_sys/param.json" "$sdk/bin/prospero-lld" "$vulkan/tools/radv-link.sh" \
        "$vulkan/runtime/libc.prx" "$lld21_config"; do
    [[ -e $file ]] || { echo "link-title.sh: missing $file" >&2; exit 2; }
done
mkdir -p "$work/link/obj" "$work/link/stubs"
cc() { PS5_PAYLOAD_SDK="$sdk" sh "$vulkan/tooling/prospero-clang18" "$@"; }

# The CRT: static constructors, main, then catchReturnFromMain (the title's).
cc -std=c++20 -O2 -fno-exceptions -fno-rtti -c "$native/app_crt.cpp" -o "$work/link/obj/app_crt.o"
# The virtual current directory (ps5/runtime/ps5_vcwd.c): relative paths resolve
# against /app0, chdir() and getcwd() work. Every libc path function below is
# wrapped, for the title's code and for libc++, SDL and DXVK alike.
cc -std=c11 -O2 -fno-omit-frame-pointer -c "$here/../runtime/ps5_vcwd.c" -o "$work/link/obj/ps5_vcwd.o"
vcwd_flags=()
for name in open fopen freopen stat lstat access opendir mkdir rmdir unlink remove rename chmod \
        chdir getcwd realpath; do
    vcwd_flags+=("--wrap=$name")
done
# libc++'s std::filesystem calls pathconf(), which no module a title loads exports.
# Both stay local: the console's WebKit POSIX module exports __wrap_access,
# __wrap_getcwd and __wrap_lstat of its own, and a name a module also defines
# would otherwise be exported from the title, which the native tool refuses.
printf '{\n    local:\n        pathconf;\n        __wrap_*;\n};\n' > "$work/link/vcwd-local.map"
vcwd_flags+=(--defsym=pathconf=ps5_title_pathconf --version-script "$work/link/vcwd-local.map")
# libc functions the SDK headers declare but no console module exports.
cc -std=c11 -O2 -fno-omit-frame-pointer -c "$here/../runtime/ps5_libc_compat.c" -o "$work/link/obj/ps5_libc_compat.o"
# Defined only by libScePosixForWebKit's stub, whose module gives a title nothing:
# fnmatch (ps5_libc_compat.c), and the platform layer's resolver functions (they
# answer "not found": no name lookups yet) and isatty (no descriptor a title
# holds is a terminal; FFmpeg's log asks), bound when the pinned SDK has them.
# Kept local, as the recipe keeps its bound names.
compat_flags=(--defsym=fnmatch=ps5_title_fnmatch)
platform_symbols=$("$sdk/bin/llvm-nm" --defined-only "$sdk/target/lib/libps5platform.a" 2>/dev/null || true)
for name in gethostbyname gethostbyaddr isatty; do
    if grep -q " T ps5_$name$" <<<"$platform_symbols"; then
        compat_flags+=("--defsym=$name=ps5_$name")
    fi
done
{
    printf '{\n    local:\n'
    for flag in "${compat_flags[@]}"; do
        flag=${flag#--defsym=}
        printf '        %s;\n' "${flag%%=*}"
    done
    printf '};\n'
} > "$work/link/compat-local.map"
compat_flags+=(--version-script "$work/link/compat-local.map")

# Link-only stubs for modules the public SDK has no stubs for: AGC (RADV's
# command submission) and the mouse.
stub() {
    local library=$1 source=$2
    cc -std=c11 -O2 -fPIC -c "$source" -o "$work/link/obj/${library}_stub.o"
    "$sdk/bin/prospero-lld" --shared -soname "${library}.prx" \
        -o "$work/link/stubs/${library}.so" "$work/link/obj/${library}_stub.o"
}
stub libSceAgc "$vulkan/vendor/ps5/sdk/stubs/agc_canary_link_stub.c"
stub libSceAgcDriver "$vulkan/vendor/ps5/sdk/stubs/agc_driver_canary_link_stub.c"
stub libSceMouse "$here/../stubs/mouse_link_stub.c"
stubs=("$work/link/stubs/libSceAgc.so" "$work/link/stubs/libSceAgcDriver.so" "$work/link/stubs/libSceMouse.so")

# shellcheck source=/dev/null
source "$vulkan/tools/radv-link.sh"
radv_link_recipe "$vulkan" "$sdk" "$archive" || exit 2
# localeconv in the C locale ('.' as the decimal point; the console's has none):
# the platform layer's, kept local as the recipe keeps its bound names.
if grep -q " T ps5_localeconv$" <<<"$("$sdk/bin/llvm-nm" --defined-only "$sdk/target/lib/libps5platform.a" 2>/dev/null)" &&
        [[ " ${radv_link_flags[*]} " != *" --defsym=localeconv=ps5_localeconv "* ]]; then
    printf '{\n    local:\n        localeconv;\n};\n' > "$work/link/localeconv-local.map"
    radv_link_flags+=(--defsym=localeconv=ps5_localeconv --version-script "$work/link/localeconv-local.map")
fi

objects=() archives=()
for input in "${inputs[@]}"; do
    case $input in
        *.a) archives+=("$input") ;;
        *) objects+=("$input") ;;
    esac
done

LLVM_CONFIG=$lld21_config "$sdk/bin/prospero-lld" "${radv_linker_script[@]}" -z nodynamic-undefined-weak \
    --eh-frame-hdr "${radv_link_flags[@]}" "${vcwd_flags[@]}" "${compat_flags[@]}" \
    --version-script "$native/app-symbols.map" --exclude-libs=ALL \
    -e _start -o "$work/link/llvm-pie.elf" \
    "$work/link/obj/app_crt.o" "$work/link/obj/ps5_vcwd.o" "$work/link/obj/ps5_libc_compat.o" "${objects[@]}" \
    --start-group "${archives[@]}" --end-group \
    "${stubs[@]}" \
    "${radv_link_inputs[@]}" \
    --as-needed "$sdk"/target/lib/*.so

# An import that no module a title loads exports is null at run time: its first
# call jumps to address 0. Refuse such a title here rather than on the console.
null_imports=$(comm -23 \
    <("$sdk/bin/llvm-nm" -D --undefined-only "$work/link/llvm-pie.elf" |
        awk '$1 == "U" { sub(/@.*/, "", $2); print $2 }' | sort -u) \
    <(for library in "$sdk"/target/lib/*.so "${stubs[@]}"; do
        case ${library##*/} in libkernel_sys.so | libScePosixForWebKit.so) continue ;; esac
        "$sdk/bin/llvm-nm" -D --defined-only "$library" 2>/dev/null | awk '{ print $NF }'
    done | sort -u))
if [[ -n $null_imports ]]; then
    echo "link-title.sh: imports no module a title loads exports (null at run time): ${null_imports//$'\n'/ }" >&2
    exit 1
fi

stub_args=()
for s in "${stubs[@]}"; do stub_args+=(--stub "$s"); done
"$tool" link --in "$work/link/llvm-pie.elf" --out "$work/eboot.elf.new" \
    --stub-dir "$sdk/target/lib" "${stub_args[@]}" --module-sdk 0x02000009 \
    --companion-sdk 0x08050001 --file-name eboot.elf

mkdir -p "$app/sce_sys" "$app/sce_module"
"$tool" self --sign --in "$work/eboot.elf.new" --out "$app/eboot.bin" --magic 0x1D3D154F
"$tool" self --inspect --file "$app/eboot.bin" > /dev/null
cp "$sce_sys/param.json" "$app/sce_sys/param.json"
for asset in icon0.png pic0.dds pic1.dds snd0.at9; do
    [[ -f $sce_sys/$asset ]] && cp "$sce_sys/$asset" "$app/sce_sys/$asset"
done
(cd "$vulkan/runtime" && sha256sum --check --strict --quiet libc.prx.sha256)
cp "$vulkan/runtime/libc.prx" "$app/sce_module/libc.prx"
mv "$work/eboot.elf.new" "$work/eboot.elf"
printf '==> %s (eboot.bin %s bytes)\n' "$app" "$(stat -c %s "$app/eboot.bin")"
