# C&C Generals for PS5: licences

This program is the PS5 port of Command & Conquer: Generals from
https://github.com/TheRealRetro/cnc-generals-ps5. It is free software under the
GNU General Public License, version 3 or later (`LICENSE`), with Electronic
Arts' additional terms under its section 7 (`EA-ADDITIONAL-TERMS.md`).

Its complete source is that repository at the release this image came from:
the scripts, the PS5 runtime, the patches to GeneralsX, SDL and DXVK, and the
pinned upstream projects its README lists, which its scripts fetch and build.

It contains no game data. Command & Conquer is a trademark of Electronic Arts
Inc.; this program is not endorsed by or affiliated with Electronic Arts or
Sony Interactive Entertainment.

## What it is built from

| Component | Version | Licence | Text in this folder |
| --- | --- | --- | --- |
| GeneralsX (Electronic Arts' Generals source release), with this port's patch | `0fc17c648c1c` | GPL-3.0-or-later with EA's terms | `LICENSE`, `EA-ADDITIONAL-TERMS.md` |
| GameSpy SDK (as GeneralsX fetches it) | | BSD-3-Clause | `GameSpy-LICENSE` |
| GameMath (from FreeBSD msun and FDLIBM) | | BSD-2-Clause, public domain | `GameMath-LICENSE.md` |
| LZH-Light | 1.0 | its own permissive notice | `LZHL.txt` |
| zlib | 1.1.4 | Zlib | `zlib-1.1.4.txt` |
| miniaudio | 0.11.25 | public domain or MIT-0 | `miniaudio-LICENSE` |
| stb | | MIT or public domain | `stb-LICENSE` |
| SDL, with this port's PS5 drivers | 3.4.2 | Zlib | `SDL-LICENSE.txt` |
| SDL_image | 3.4.0 | Zlib | `SDL_image-LICENSE.txt` |
| FreeType | 2.13.3 | FreeType Licence (FTL) | `FreeType-LICENSE.TXT`, `FreeType-FTL.TXT` |
| GLM and gli | 1.0.1 | MIT | `GLM-copying.txt` |
| DXVK, with this port's patch | 2.6 | Zlib/libpng | `DXVK-LICENSE` |
| libdisplay-info (in DXVK) | | MIT | `libdisplay-info-LICENSE` |
| FFmpeg (Bink demuxer and decoders, swscale; unmodified) | 7.1.1 | LGPL-2.1-or-later | `FFmpeg-COPYING.LGPLv2.1`, `FFmpeg-LICENSE.md` |
| Mesa RADV, ACO (PS5_Mesa `47e9eb61ee71`, built by PS5_Vulkan `252bf912a745`) | | MIT (Mesa's per-file licences) | `Mesa-license.rst`, `Mesa-MIT` |
| PS5_Vulkan title runtime, PS5_PayloadSDK platform layer | | GPL-3.0-or-later | `LICENSE` |
| `sce_module/libc.prx`: the clean-room module from ps5-native-app-boilerplate | | GPL-3.0-or-later | `LICENSE` |
| LLVM libc++, libc++abi, libunwind, compiler-rt builtins | | Apache-2.0 WITH LLVM-exception | (the exception covers object code in a program) |
| Liberation fonts; Liberation Sans Narrow | 2.1.5; 1.07.6 | SIL Open Font License 1.1 | `../fonts/LICENSE-Liberation*.txt` |

Portions of this software are copyright © 2024 The FreeType Project
(www.freetype.org). All rights reserved.

This software uses code of FFmpeg (https://ffmpeg.org) licensed under the
LGPLv2.1, unmodified; its source is at
https://github.com/FFmpeg/FFmpeg/tree/n7.1.1. The repository above builds it
(`scripts/build-ffmpeg.sh`) and links the program again with any FFmpeg build.
