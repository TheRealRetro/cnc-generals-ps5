#!/usr/bin/env python3
"""Check a .ffpkg's UFS2 file system the way the console's kernel will read it.

The PS5 kernel is FreeBSD's: it mounts an image only if the superblock passes
FreeBSD's checks (ffs_mountfs and validate_sblock in sys/ufs/ffs/), then reads
blocks at fsbtodb() addresses in 512-byte units. This applies those checks, so
a bad image fails here rather than as "nmount ... Invalid argument" in
ShadowMountPlus's debug.log, and with a source directory it walks the image
from the root inode, as the kernel would, comparing every file with the source.

Usage: check-ufs2.py IMAGE [SOURCE_DIR]   (exit status 1 on failure)
"""
import os
import stat
import struct
import sys

SBLOCK_UFS2 = 65536
SBLOCKSIZE = 8192
DEV_BSIZE = 512           # the kernel addresses every disk in 512-byte blocks
MAXBSIZE = 65536
MAXFRAG = 8
FS_MAXCONTIG = 16
FS_UFS2_MAGIC = 0x19540119
CG_MAGIC = 0x090255
UFS_ROOTINO = 2
UFS_NDADDR, UFS_NIADDR = 12, 3
UFS2_DINODE_SIZE = 256
CSUM_SIZE = 16
DIRBLKSIZ = 512

# Field offsets in struct fs (sys/ufs/ffs/fs.h).
FIELDS = {
    "sblkno": (0x08, "i"), "cblkno": (0x0C, "i"), "iblkno": (0x10, "i"), "dblkno": (0x14, "i"),
    "ncg": (0x2C, "I"), "bsize": (0x30, "i"), "fsize": (0x34, "i"), "frag": (0x38, "i"),
    "minfree": (0x3C, "i"), "bmask": (0x48, "i"), "fmask": (0x4C, "i"), "bshift": (0x50, "i"),
    "fshift": (0x54, "i"), "maxcontig": (0x58, "i"), "fragshift": (0x60, "i"),
    "fsbtodb": (0x64, "i"), "sbsize": (0x68, "i"), "nindir": (0x74, "i"), "inopb": (0x78, "I"),
    "cssize": (0x9C, "i"), "cgsize": (0xA0, "i"), "ipg": (0xB8, "I"), "fpg": (0xBC, "i"),
    "maxbsize": (0x35C, "i"), "sblockloc": (0x3E8, "q"), "size": (0x438, "q"),
    "dsize": (0x440, "q"), "csaddr": (0x448, "q"), "contigsumsize": (0x524, "i"),
    "maxsymlinklen": (0x528, "i"), "qbmask": (0x538, "q"), "qfmask": (0x540, "q"),
    "magic": (0x55C, "i"),
}


def ilog2(value):
    return value.bit_length() - 1


def roundup(x, y):
    return (x + y - 1) // y * y


def howmany(x, y):
    return (x + y - 1) // y


def read_superblock(image, offset):
    image.seek(offset)
    raw = image.read(SBLOCKSIZE)
    if len(raw) < SBLOCKSIZE:
        return None
    return {name: struct.unpack_from("<" + fmt, raw, at)[0] for name, (at, fmt) in FIELDS.items()}


def superblock_problems(fs):
    if fs["magic"] != FS_UFS2_MAGIC:
        return ["magic %#x is not UFS2's (little-endian)" % fs["magic"]]
    rules = [
        ("sblockloc", fs["sblockloc"] == SBLOCK_UFS2),
        ("maxsymlinklen", fs["maxsymlinklen"] == (UFS_NDADDR + UFS_NIADDR) * 8),
        ("nindir", fs["nindir"] == fs["bsize"] // 8),
        ("inopb", fs["inopb"] == fs["bsize"] // UFS2_DINODE_SIZE),
        ("bsize", MAXBSIZE >= fs["bsize"] >= 4096 and fs["bsize"] & (fs["bsize"] - 1) == 0),
        ("fsize", DEV_BSIZE <= fs["fsize"] <= fs["bsize"] and fs["fsize"] * MAXFRAG >= fs["bsize"]
                  and fs["fsize"] & (fs["fsize"] - 1) == 0),
        ("frag", fs["frag"] == fs["bsize"] // fs["fsize"]),
        ("fsbtodb", fs["fsbtodb"] == ilog2(fs["fsize"] // DEV_BSIZE)),
        ("bshift", fs["bshift"] == ilog2(fs["bsize"])),
        ("fshift", fs["fshift"] == ilog2(fs["fsize"])),
        ("fragshift", fs["fragshift"] == ilog2(fs["frag"])),
        ("bmask", fs["bmask"] == ~(fs["bsize"] - 1)),
        ("fmask", fs["fmask"] == ~(fs["fsize"] - 1)),
        ("qbmask", fs["qbmask"] == ~fs["bmask"]),
        ("qfmask", fs["qfmask"] == ~fs["fmask"]),
        ("sbsize", fs["sbsize"] <= SBLOCKSIZE),
        ("maxbsize", fs["maxbsize"] == 0 or (fs["bsize"] <= fs["maxbsize"] <= FS_MAXCONTIG * fs["bsize"])),
        ("ncg", fs["ncg"] >= 1),
        ("fpg", fs["fpg"] >= 3 * fs["frag"]),
        ("ipg", fs["ipg"] >= fs["inopb"]),
        ("sblkno", fs["sblkno"] == roundup(howmany(fs["sblockloc"] + SBLOCKSIZE, fs["fsize"]), fs["frag"])),
        ("cblkno", fs["cblkno"] == fs["sblkno"] + roundup(howmany(SBLOCKSIZE, fs["fsize"]), fs["frag"])),
        ("iblkno", fs["iblkno"] == fs["cblkno"] + fs["frag"]),
        ("dblkno", fs["dblkno"] == fs["iblkno"] + fs["ipg"] // (fs["inopb"] // fs["frag"])),
        ("cgsize", fs["fsize"] <= fs["cgsize"] <= fs["bsize"] and fs["cgsize"] % fs["fsize"] == 0),
        ("cssize", fs["cssize"] == roundup(fs["ncg"] * CSUM_SIZE, fs["fsize"])),
        ("csaddr", fs["csaddr"] >= 0),
        ("size", (fs["ncg"] - 1) * fs["fpg"] < fs["size"] <= fs["ncg"] * fs["fpg"]),
        ("dsize", 0 < fs["dsize"] <= fs["size"]),
        ("minfree", 0 <= fs["minfree"] <= 99),
        ("maxcontig", fs["maxcontig"] >= 0
                      and (fs["maxcontig"] != 0 or fs["contigsumsize"] == 0)
                      and (fs["maxcontig"] <= 1 or fs["contigsumsize"] == min(fs["maxcontig"], FS_MAXCONTIG))),
    ]
    return ["fs_%s = %d" % (name, fs.get(name, 0)) for name, ok in rules if not ok]


class Ufs2Reader:
    """Reads files the way FreeBSD's kernel does: block addresses through fsbtodb()."""

    def __init__(self, image, fs):
        self.image = image
        self.fs = fs

    def read_blocks(self, fsba, length):
        # bread(devvp, fsbtodb(fs, fsba), ...): fsbtodb shifts to 512-byte disk blocks.
        self.image.seek((fsba << self.fs["fsbtodb"]) * DEV_BSIZE)
        return self.image.read(length)

    def inode(self, ino):
        fs = self.fs
        cg, index = divmod(ino, fs["ipg"])
        fsba = cg * fs["fpg"] + fs["iblkno"] + (index // fs["inopb"]) * fs["frag"]
        raw = self.read_blocks(fsba, fs["bsize"])
        return raw[(index % fs["inopb"]) * UFS2_DINODE_SIZE:][:UFS2_DINODE_SIZE]

    def block_addresses(self, dinode):
        """Every data block address of a file, in order (direct, then indirect levels)."""
        fs = self.fs
        size = struct.unpack_from("<Q", dinode, 16)[0]
        count = howmany(size, fs["bsize"])
        direct = struct.unpack_from("<12q", dinode, 112)
        indirect = struct.unpack_from("<3q", dinode, 208)
        addresses = list(direct[:count])

        def expand(fsba, level, want):
            pointers = struct.unpack("<%dq" % fs["nindir"], self.read_blocks(fsba, fs["bsize"]))
            if level == 0:
                return list(pointers[:want])
            span = fs["nindir"] ** level
            result = []
            for pointer in pointers:
                if want <= 0:
                    break
                result += expand(pointer, level - 1, min(want, span))
                want -= span
            return result

        remaining = count - len(addresses)
        for level, fsba in enumerate(indirect):
            if remaining <= 0:
                break
            span = fs["nindir"] ** (level + 1)
            addresses += expand(fsba, level, min(remaining, span))
            remaining -= span
        return size, addresses

    def file_chunks(self, dinode):
        fs = self.fs
        size, addresses = self.block_addresses(dinode)
        left = size
        for fsba in addresses:
            length = min(left, fs["bsize"])
            yield b"\0" * length if fsba == 0 else self.read_blocks(fsba, length)
            left -= length

    def directory(self, dinode):
        data = b"".join(self.file_chunks(dinode))
        entries = {}
        for block in range(0, len(data), DIRBLKSIZ):
            offset = block
            while offset < block + DIRBLKSIZ:
                ino, reclen, _type, namlen = struct.unpack_from("<IHBB", data, offset)
                if reclen == 0:
                    raise ValueError("directory entry with zero length")
                if ino != 0:
                    name = data[offset + 8:offset + 8 + namlen].decode("utf-8", "surrogateescape")
                    if name not in (".", ".."):
                        entries[name] = ino
                offset += reclen
        return entries


def compare_tree(reader, source):
    problems = []
    checked = 0

    def walk(ino, path, relative):
        nonlocal checked
        dinode = reader.inode(ino)
        mode = struct.unpack_from("<H", dinode, 0)[0]
        if stat.S_ISDIR(os.lstat(path).st_mode):
            if not stat.S_ISDIR(mode):
                problems.append("%s: not a directory in the image" % relative)
                return
            entries = reader.directory(dinode)
            names = set(os.listdir(path))
            for name in sorted(names - set(entries)):
                problems.append("%s: missing from the image" % os.path.join(relative, name))
            for name in sorted(set(entries) - names):
                problems.append("%s: in the image only" % os.path.join(relative, name))
            for name in sorted(names & set(entries)):
                walk(entries[name], os.path.join(path, name), os.path.join(relative, name))
            return
        if not stat.S_ISREG(mode):
            problems.append("%s: not a regular file in the image" % relative)
            return
        size = struct.unpack_from("<Q", dinode, 16)[0]
        if size != os.path.getsize(path):
            problems.append("%s: %d bytes in the image, %d in the source" % (relative, size, os.path.getsize(path)))
            return
        with open(path, "rb") as original:
            for chunk in reader.file_chunks(dinode):
                if chunk != original.read(len(chunk)):
                    problems.append("%s: contents differ" % relative)
                    return
        checked += 1

    walk(UFS_ROOTINO, source, ".")
    return problems, checked


def main(args):
    if not 1 <= len(args) <= 2:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    path = args[0]
    with open(path, "rb") as image:
        fs = read_superblock(image, SBLOCK_UFS2)
        if fs is None:
            print("%s: too small to hold a UFS2 superblock" % path)
            return 1
        problems = superblock_problems(fs)
        if problems:
            print("%s: FAILS the kernel's superblock checks:" % path)
            for problem in problems:
                print("    " + problem)
            return 1
        image.seek(fs["cblkno"] * fs["fsize"] + 4)
        if struct.unpack("<i", image.read(4))[0] != CG_MAGIC:
            print("%s: cylinder group 0 has no CG_MAGIC" % path)
            return 1
        print("%s: UFS2 superblock OK (fsize %d, fsbtodb %d, %d cylinder groups)"
              % (path, fs["fsize"], fs["fsbtodb"], fs["ncg"]))
        if len(args) == 2:
            problems, checked = compare_tree(Ufs2Reader(image, fs), args[1])
            if problems:
                print("%s: differs from %s:" % (path, args[1]))
                for problem in problems[:50]:
                    print("    " + problem)
                return 1
            print("%s: all %d files read back from the root inode match %s" % (path, checked, args[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
