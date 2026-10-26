#!/usr/bin/env bash
# CMake's executable link rule for PS5 titles (GeneralsX cmake/ps5.cmake):
#
#   cmake-link.sh SCE_SYS_DIR DIST_DIR TARGET ARG...
#
# ARG is CMake's <OBJECTS> <LINK_LIBRARIES>: objects and static archives go to
# link-title.sh, which links with RADV and assembles DIST_DIR; compiler-driver
# flags (-l, -L, -Wl, -pthread...) are dropped, since a title's system
# libraries are the SDK's module stubs, which link-title.sh adds itself.
# TARGET receives the linked ELF so CMake sees its output.
#
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

sce_sys=$1 dist=$2 target=$3
shift 3

inputs=()
for arg in "$@"; do
    case $arg in
        *.o | *.obj | *.a) inputs+=("$(realpath -- "$arg")") ;;
        -*) ;; # driver flags
        *) echo "cmake-link.sh: ignoring link input $arg" >&2 ;;
    esac
done

work="$(dirname -- "$(realpath -m -- "$target")")/ps5-link"
mkdir -p "$work"
bash "$here/link-title.sh" "$work" "$sce_sys" "$dist" "${inputs[@]}"
cp "$work/eboot.elf" "$target"
