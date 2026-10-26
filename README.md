# C&C Generals for PS5 (native homebrew port)

A native PlayStation 5 homebrew build of **Command & Conquer: Generals** from
EA's GPL-3.0 source release
([electronicarts/CnC_Generals_Zero_Hour](https://github.com/electronicarts/CnC_Generals_Zero_Hour)),
packaged as a ShadowMountPlus `.ffpkg` (UFS2) image.

It is built on [GeneralsX](https://github.com/fbraz3/GeneralsX), a fork of EA's
code (via TheSuperHackers) that already runs 64-bit on Linux and macOS through
DXVK (DirectX 8 to Vulkan), SDL3 and MiniAudio. This port swaps the
desktop platform pieces for PS5 ones.

**Status: playable.** On a PS5 (firmware 13.60, ShadowMountPlus) with the
retail 1.00 discs: the menus, skirmish, the campaign and its videos, Options,
the DualSense and sound all work, from an image with the game data or one
without it ([below](#the-image-without-game-data)). Not yet tested: saving and
loading, USB mouse and keyboard, LAN. See [Milestones](#milestones).

Game data is **not** included. You need your own retail copy; the `.ffpkg`
built from it contains EA's files and is for your own console only.

## Stack

| Layer | Desktop GeneralsX | PS5 |
| --- | --- | --- |
| Game code | GeneralsX (EA source, 64-bit) | same, `ps5` branch in `GeneralsX/` |
| Graphics | DXVK 2.6 (`.so`, loaded at runtime) | DXVK built as static libraries |
| Vulkan driver | system Mesa/NVIDIA | RADV for PS5 ([PS5_Vulkan](https://github.com/mihawk-99/PS5_Vulkan) from [PS5_Mesa](https://github.com/mihawk-99/PS5_Mesa)), linked into the title |
| Window, input, events | SDL3 | SDL3 with PS5 drivers: `VK_KHR_display` surface, DualSense, USB mouse and keyboard |
| Audio | MiniAudio | MiniAudio with a `sceAudioOut` backend |
| Videos (Bink) | FFmpeg | FFmpeg 7.1 with only the Bink demuxer and decoders (LGPL) |
| Online | GeneralsOnline, curl | off (GameSpy's servers are gone; LAN untested) |
| libc gaps, heap, threads | glibc | [PS5_PayloadSDK](https://github.com/mihawk-99/PS5_PayloadSDK) platform layer |
| Packaging | — | signed `eboot.bin` + `sce_sys/` title folder, then `.ffpkg` |

## Layout

| Path | What |
| --- | --- |
| `scripts/mkffpkg.sh` | title folder to `.ffpkg` (UFS2) on Linux/WSL, ShadowMountPlus's profile |
| `scripts/build-makefs.sh`, `check-ufs2.py` | the makefs `mkffpkg.sh` needs, and the image check it runs |
| `scripts/symbolize-crash.sh` | names the addresses of a crash in `generals.log` |
| `scripts/extract-generals-data.sh` | rebuild the installed game folder from the retail disc copies |
| `scripts/build-sdl3.sh`, `build-dxvk.sh`, `build-ffmpeg.sh` | SDL3, DXVK and FFmpeg static libraries for the PS5 |
| `scripts/build-d3d8test.sh` | the D3D8 smoke test title, packed as `.ffpkg` |
| `scripts/build-generals.sh`, `package-generals.sh` | the game title, and its `.ffpkg` with your game data or (`--without-data`) without |
| `ps5/runtime/` | title lifecycle (stderr to klog, exit through the shell), a virtual current directory, libc functions the console lacks |
| `ps5/tools/link-title.sh` | link with RADV (PS5_Vulkan's recipe), sign, assemble the title folder |
| `ps5/d3d8test/` | the D3D8 smoke test |
| `patches/` | this port's changes to GeneralsX, SDL and DXVK, one patch each |
| `scripts/fetch-sources.sh`, `upstreams.sh` | fetch the three at their pinned commits and apply `patches/` |
| `scripts/export-patches.sh` | write `patches/` again from the checkouts' `ps5` branches |
| `GeneralsX/` | GeneralsX checkout, branch `ps5` (fetched, not in this repo) |
| `SDL/` | SDL 3.4.2, branch `ps5`: PS5 video (`VK_KHR_display`), DualSense, USB keyboard/mouse and AudioOut drivers (fetched) |
| `dxvk/` | DXVK 2.6, branch `ps5`: static D3D8/D3D9, SDL3 and Vulkan linked into the title (fetched) |
| `Data Files/` | your disc copies (ignored, never commit) |
| `out/` | built images (ignored) |

The PS5 dependencies and build trees live in WSL at `/root/ps5-generals/`
(`$PS5_GENERALS_WS`, see `scripts/env.sh`).

## Building (WSL Ubuntu 24.04)

The game's sources: GeneralsX, SDL and DXVK at their pinned commits, with this
port's patches applied, into `GeneralsX/`, `SDL/` and `dxvk/`:

```bash
bash scripts/fetch-sources.sh
```

The PS5 toolchain, in `$PS5_GENERALS_WS/deps/` (set up by hand so far; the
revisions are those in [Pinned upstreams](#pinned-upstreams)):

| Dependency | Used for |
| --- | --- |
| [PS5_Vulkan](https://github.com/mihawk-99/PS5_Vulkan) | RADV built for the console (its `tools/build-radv.sh`, from PS5_Mesa), the title link recipe, the native tool that signs `eboot.bin`, `libc.prx` |
| [PS5_Mesa](https://github.com/mihawk-99/PS5_Mesa) | RADV's source |
| [PS5_VulkanTemplate](https://github.com/mihawk-99/PS5_VulkanTemplate) | its `.deps/native/ps5-payload-sdk` is the SDK titles build with |
| [PS5_VKHomebrewUI](https://github.com/mihawk-99/PS5_VKHomebrewUI) | beside PS5_VulkanTemplate, which its link step reads |
| LLVM 21.1.8 `lld` | the final link only, in `$PS5_GENERALS_WS/toolchains/llvm-21` |

Host packages:

```bash
apt install bmake curl msitools clang lld llvm cmake ninja-build glslang-tools zstd \
  python3-numpy python3-pil python3-mako python3-markupsafe pipx
pipx install meson   # Mesa needs meson >= 1.4
bash scripts/build-makefs.sh   # makefs for .ffpkg images, see below
```

Ubuntu's own `makefs` package cannot make `.ffpkg` images: it puts a UFS2
superblock at UFS1's offset, so the console's kernel refuses the image
(ShadowMountPlus: `nmount rdonly failed: Invalid argument`).
`scripts/build-makefs.sh` builds it from the same source with the FreeBSD
superblock location, and `mkffpkg.sh` runs `scripts/check-ufs2.py` on every
image: FreeBSD's superblock checks, then every file read back from the root
inode and compared with the title folder.

Extract the game data from the disc copies:

```bash
bash scripts/extract-generals-data.sh "Data Files" /root/ps5-generals/gamedata/generals
```

Build the PS5 libraries once, then the game, then pack it with your game data:

```bash
bash scripts/build-sdl3.sh && bash scripts/build-deps.sh && bash scripts/build-ffmpeg.sh && bash scripts/build-dxvk.sh
bash scripts/build-generals.sh
bash scripts/package-generals.sh   # out/PPSA99203-generals.ffpkg
```

`build-generals.sh` cross-compiles GeneralsX's `g_generals` with the PS5
toolchain; its link step (`ps5/tools/cmake-link.sh`) links RADV, binds the libc
gaps (`ps5/runtime/`), signs `eboot.bin` and assembles `dist/PPSA99203`.

Pack any title folder:

```bash
bash scripts/mkffpkg.sh dist/PPSA99203 out/PPSA99203.ffpkg
```

## The image without game data

`package-generals.sh --without-data` packs `out/PPSA99203-generals-nodata.ffpkg`:
the game's code, its PS5 runtime and the Liberation fonts, nothing of EA's.
That is the image to share. Each player provides their own game files:

1. From your own Generals installation (the folder with `INI.big`), copy every
   `.big` file and the `Data` folder to `/data/generals` on the console (FTP).
   A 1.08-patched installation is best (see [Game data version](#game-data-version)).
2. Install the image as below and start the game.

The game looks for `INI.big` in the image itself, then in `/data/generals`,
then in `generals` on a USB drive if the console lets the game see it. With no
game data it shows a notification saying what to copy, and closes. Both were
tested on the console (2026-10-26): the notification without data, and the
game with the data in `/data/generals`.

Distributing the image means distributing GPL code: offer its source with it
(this repository, the patches it applies, and the pinned upstreams).

## Installing on the PS5

Requires a console you own with a homebrew environment (etaHEN or similar
plus [ShadowMountPlus](https://github.com/drakmor/ShadowMountPlus)). Copy the
`.ffpkg` to `/data/homebrew/` (FTP) or a `homebrew/` folder on a USB drive;
ShadowMountPlus mounts it and adds the tile. If it does not appear, read
`/data/shadowmount/debug.log`.

The game writes its log to `/data/generals/generals.log` (fetch it over FTP).
If it crashes, the log ends with `CRASH:` lines; name them with the ELF that
`package-generals.sh` kept for that build:

```bash
bash scripts/symbolize-crash.sh generals.log
```

Settings, saves and the Vulkan shader cache live in the title's download data
(`/download0`).

## Controls

A USB mouse and keyboard work as on PC. The DualSense drives the same mouse
cursor and hotkeys, and the two can be mixed:

| DualSense | Game |
| --- | --- |
| Left stick | move the cursor |
| Right stick | scroll the map (analog, at up to the keyboard scroll speed) |
| Cross | left click: select, confirm |
| Circle | right click: move, attack, cancel |
| L1 (hold) | Shift: add to selection; with D-pad, add to a group |
| R1 (hold) | Ctrl: force fire; with D-pad, assign a group |
| L2 / R2 | zoom out / zoom in |
| D-pad | select control groups 1-4 |
| Triangle | E: select all of this unit type on screen |
| Square | S: stop |
| L3 | H: jump to the command center |
| R3 | reset the camera |
| Touchpad click | Space: jump to the last event |
| OPTIONS | Esc: pause menu |

Waypoints (hold Alt) and the other hotkeys need the keyboard.

## Game data version

GeneralsX is written against the 1.08 patch; the discs are 1.00. Skirmish
plays with 1.00 data, but screens a later patch extended can name controls the
1.00 layouts lack (the Options menu's alternate-mouse checkbox crashed it).
Every control the code names was checked against the 1.00 `Window.big`; the
offline screens are guarded. Patching your PC install to 1.08 and extracting
from that avoids the class of problem altogether.

## Milestones

1. **Pipeline**: title link, signing and `.ffpkg` packing. Done: the first console test (FW 13.60) found the images unmountable, fixed in `build-makefs.sh`; the rebuilt game image mounts, installs and launches.
2. **Driver**: RADV release archive built for the console; PS5_VulkanTemplate's sample title (`PPSA99130`) rebuilt with it as a known-good Vulkan check. Done: the game renders with this driver on the console.
3. **DXVK on PS5**: D3D8 smoke test title (`PPSA99204`, `ps5/d3d8test/`): SDL3 with PS5 drivers + DXVK D3D8 + RADV, DualSense, USB mouse and keyboard. Done: the game runs on this stack on the console.
4. **Engine boots**: GeneralsX reaches the main menu. **Reached** on a PS5 (FW 13.60, ShadowMountPlus 1.7-beta5fix1) with `PPSA99203-generals.ffpkg`, 2026-10-14.
5. **Playable**: skirmish with DualSense + mouse/keyboard, audio. **Reached** 2026-10-14: a full skirmish with the DualSense through to the score screen, Options in the menu and in game, and a clean exit, on the 1.00 data. Untested: USB mouse and keyboard.
6. **Complete**: campaign videos (Bink via FFmpeg), saves, LAN. The campaign and its videos (EA logo, intro, briefings) play on the console (2026-10-14). Untested: saves and loads, LAN.

## Pinned upstreams

| Project | Revision |
| --- | --- |
| GeneralsX | `0fc17c648c1c` (main, 2026-10-07) |
| ps5-native-app-boilerplate | `b8dc4a3fe2e0` |
| PS5_Vulkan | `252bf912a745` |
| PS5_Mesa | `47e9eb61ee71` (PS5_Vulkan's pin) |
| PS5_VulkanTemplate | `91179df760df` (its SDK pin of PS5_PayloadSDK is what titles build with) |
| PS5_VKHomebrewUI | `2188642afbcc` |
| SDL | `release-3.4.2` (`683181b47cfa`) |
| DXVK | `v2.6` (`ad253b8a`) |
| FFmpeg | `n7.1.1` (`db69d06eeeab`) |
| makefs | Ubuntu `20190105-3` source, superblock patch (`build-makefs.sh`) |
| LLVM (link only) | 21.1.8 `lld`, `/root/ps5-generals/toolchains/llvm-21` |

## Licence

GPL-3.0-or-later, with EA's additional terms: see [LICENSE.md](LICENSE.md)
(EA's source release, as GeneralsX carries it). The patches to SDL (zlib) and
DXVK (zlib/libpng) are under their projects' licences; FFmpeg is built as
LGPL 2.1+. Command & Conquer is a trademark of Electronic Arts; this project is
not endorsed by EA or Sony. No game data is included: you need your own copy.
