#!/usr/bin/env bash
# Build the makefs that mkffpkg.sh uses: Ubuntu's makefs (20190105-3, a MirBSD
# snapshot of NetBSD's) with its UFS2 superblock where FreeBSD looks for it.
#
# That makefs writes a UFS2 superblock at UFS1's offset (8192) and lays the file
# system out around it ("#if 0 /* XXX makefs is used for small filesystems. */"
# in ffs/mkfs.c). FreeBSD, and so the PS5's kernel, only takes a UFS2 superblock
# from 65536, and ShadowMountPlus's mount fails with "Invalid argument".
# FreeBSD's own makefs uses SBLOCK_UFS2 here; so does this one once patched.
#
# Needs: apt install bmake curl
set -euo pipefail
source "$(dirname "$0")/env.sh"

VERSION=20190105
URL=https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/makefs/$VERSION-3/makefs_$VERSION.orig.tar.gz
# From the package's makefs_20190105-3.dsc.
SHA256=691fe1487944e280c0198cf82ce2c46b91c29f424f1c4dc3c8a4c12e5bc1fd15
SRC=$PS5_GENERALS_WS/deps/makefs-src
OUT=$PS5_GENERALS_WS/toolchains/makefs

command -v bmake >/dev/null || { echo "bmake is missing: apt install bmake" >&2; exit 1; }

mkdir -p "$SRC"
cd "$SRC"
tarball=makefs_$VERSION.orig.tar.gz
[ -f "$tarball" ] || curl -fsSL -o "$tarball" "$URL"
echo "$SHA256  $tarball" | sha256sum -c --quiet
rm -rf build
mkdir build
tar -xzf "$tarball" -C build --strip-components=1

# The patch: UFS2's superblock at SBLOCK_UFS2 (65536), as in FreeBSD's makefs.
mkfs_c=build/src/usr.sbin/makefs/ffs/mkfs.c
python3 -I - "$mkfs_c" <<'PY'
import sys
path = sys.argv[1]
source = open(path).read()
before = ("#if 0 /* XXX makefs is used for small filesystems. */\n"
          "\t\tsblock.fs_sblockloc = SBLOCK_UFS2;\n"
          "#else\n"
          "\t\tsblock.fs_sblockloc = SBLOCK_UFS1;\n"
          "#endif\n")
after = ("\t\t/* PS5 C&C Generals: where FreeBSD looks for a UFS2 superblock. */\n"
         "\t\tsblock.fs_sblockloc = SBLOCK_UFS2;\n")
if source.count(before) != 1:
    sys.exit("build-makefs.sh: the superblock location code in %s is not the one expected" % path)
open(path, "w").write(source.replace(before, after))
PY

# The Debian package's build (debian/rules), without dpkg.
DEFS=(
    "-D__IDSTRING(x,y)=static const char x[] __attribute__((__used__)) = y"
    "-D__RCSID(x)=__IDSTRING(rcsid,x)"
    "-D__SCCSID(x)=__IDSTRING(sccsid,x)"
    "-D__KERNEL_RCSID(x,y)=__IDSTRING(kernelrcsid_ ## x,y)"
    "-D__dead=__attribute__((__noreturn__))"
    "-D__packed=__attribute__((__packed__))"
    "-D_DIAGASSERT(x)="
    -Dbswap16=__bswap_16 -Dbswap32=__bswap_32 -Dbswap64=__bswap_64
    -DHAVE_STRUCT_STATVFS_F_IOSIZE=0 -DHAVE_STRUCT_STAT_ST_MTIMENSEC=0
    -DHAVE_STRUCT_STAT_ST_FLAGS=0 -DHAVE_STRUCT_STAT_ST_GEN=0 -DS_ISTXT=S_ISVTX
)
topdir=$SRC/build
(
    cd build/src/usr.sbin/makefs
    printf -v CPPFLAGS '%q ' "${DEFS[@]}"
    CC=cc CFLAGS="-O2 -Wall -Wno-unused-but-set-variable -Wno-unused-result" \
    CPPFLAGS="$CPPFLAGS" LDFLAGS="-O2" \
        bmake -m /usr/share/bmake/mk-netbsd BSDSRCDIR="$topdir/src" GNUPORT=Yes NOGCCERROR=Yes makefs
)
mkdir -p "$OUT"
install -m 0755 build/src/usr.sbin/makefs/makefs "$OUT/makefs"
echo "==> $OUT/makefs (UFS2 superblock at 65536)"
