#!/usr/bin/env bash
# Fetch the upstream sources into GeneralsX/, SDL/ and dxvk/ in the project
# folder, each at its pinned commit (upstreams.sh) on a "ps5" branch with the
# port's changes from patches/ applied as one commit. Run it once after
# cloning; the build scripts then read those folders (sync-src.sh).
#
# Usage: fetch-sources.sh   (a folder that already exists is left alone)

set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project=$(dirname "$here")
. "$here/upstreams.sh"

for upstream in "${UPSTREAMS[@]}"; do
    read -r name url commit <<<"$upstream"
    dir=$project/$name
    if [ -e "$dir" ]; then
        echo "$name: already there, left alone"
        continue
    fi
    git init -q "$dir"
    git -C "$dir" remote add origin "$url"
    git -C "$dir" fetch -q --depth 1 origin "$commit"
    git -C "$dir" checkout -q -b ps5 FETCH_HEAD
    # DXVK's headers and libdisplay-info are submodules.
    git -C "$dir" submodule -q update --init --depth 1
    # The patch's author is kept; this fetch is only the committer.
    git -C "$dir" -c user.name=cnc-generals-ps5 -c user.email=cnc-generals-ps5@localhost \
        am -q "$project/patches/$name.patch"
    echo "$name: ${commit:0:12} + patches/$name.patch"
done
