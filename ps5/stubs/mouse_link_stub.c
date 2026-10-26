/*
 * Link-only stand-in for libSceMouse, which the public SDK has no stub for.
 * It gives the linker and PS5_Vulkan's native tool the import names; at run
 * time the system module (loaded with sceSysmoduleLoadModule(0x00a9)) provides
 * the functions, and these bodies are never called.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
int sceMouseInit(void) { return -1; }
int sceMouseOpen(int user, int type, int index, const void *param) { return -1; }
int sceMouseRead(int handle, void *data, int count) { return -1; }
int sceMouseClose(int handle) { return -1; }
