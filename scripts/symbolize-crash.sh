#!/usr/bin/env bash
# Name the addresses of a crash the PS5 title logged (ps5/runtime/ps5_title.c):
# its "CRASH:" lines give the faulting pc, the return addresses of the calls
# that led there, and ps5_title_init's run-time address as the anchor. Each is
# moved to the linked ELF's addresses through the anchor and named with
# llvm-symbolizer.
#
# Usage: symbolize-crash.sh generals.log [title.elf]
#   title.elf defaults to the ELF package-generals.sh kept with the last image,
#   which must be the build that logged the crash.
set -euo pipefail
source "$(dirname "$0")/env.sh"

LOG=$1
ELF=${2:-$PS5_GENERALS_WS/out/PPSA99203-generals.elf}
[ -f "$LOG" ] || { echo "no log: $LOG" >&2; exit 1; }
[ -f "$ELF" ] || { echo "no ELF: $ELF" >&2; exit 1; }
SYMBOLIZER=$(command -v llvm-symbolizer || command -v llvm-symbolizer-18 || true)
[ -n "$SYMBOLIZER" ] || { echo "llvm-symbolizer is missing (apt install llvm)" >&2; exit 1; }

# awk reads the whole listing: stopping early would end llvm-nm on a broken pipe.
link_anchor=$(llvm-nm "$ELF" | awk '$3 == "ps5_title_init" && !found { print "0x" $1; found = 1 }')
[ -n "$link_anchor" ] || { echo "ps5_title_init is not in $ELF" >&2; exit 1; }

crash=$(grep -a "CRASH:" "$LOG" | tr -d '\r')
[ -n "$crash" ] || { echo "no crash in $LOG"; exit 0; }
run_anchor=$(sed -n 's/.*anchor \(0x[0-9a-fA-F]*\).*/\1/p' <<<"$crash" | head -1)

echo "$crash" | head -1
while read -r label address; do
    offset=$(printf '0x%x' $(( address - run_anchor + link_anchor )))
    # A return address points after its call: name the call itself.
    [ "$label" = pc ] || offset=$(printf '0x%x' $(( offset - 1 )))
    printf '%-4s %s  ' "$label" "$offset"
    "$SYMBOLIZER" --obj="$ELF" --demangle --functions=linkage --no-inlines "$offset" | head -2 | paste -sd ' '
done < <(
    sed -n 's/.* pc \(0x[0-9a-fA-F]*\),.*/pc \1/p' <<<"$crash" | head -1
    sed -n 's/^.*CRASH: *\(#[0-9]*\) \(0x[0-9a-fA-F]*\).*/\1 \2/p' <<<"$crash"
)
