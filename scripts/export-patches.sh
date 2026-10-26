#!/usr/bin/env bash
# Write patches/<name>.patch from the commits on each source folder's "ps5"
# branch since its pinned commit (upstreams.sh). Commit changes there first;
# the patches are what the repository carries of GeneralsX, SDL and DXVK.
#
# Usage: export-patches.sh

set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project=$(dirname "$here")
. "$here/upstreams.sh"

mkdir -p "$project/patches"
for upstream in "${UPSTREAMS[@]}"; do
    read -r name url commit <<<"$upstream"
    if [ -n "$(git -C "$project/$name" status --porcelain)" ]; then
        echo "error: $name has uncommitted changes; commit them on ps5 first" >&2
        exit 1
    fi
    git -C "$project/$name" format-patch -q --stdout "$commit..ps5" > "$project/patches/$name.patch"
    echo "patches/$name.patch: $(git -C "$project/$name" rev-list --count "$commit..ps5") commit(s)"
done
