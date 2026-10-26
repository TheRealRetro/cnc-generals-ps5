/*
 * C&C Generals PS5 - title lifecycle: logging and the exit through the shell.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Send stderr to the console's kernel log, each line prefixed "[name] ".
 * Call first thing in main. */
void ps5_title_init(const char *name);

/* Also write stderr to a file (created or truncated), as each write reaches
 * klog, so a run's log can be fetched over FTP. Call after ps5_title_init.
 * Returns 0, or -1 with errno (stderr then goes to klog alone). */
int ps5_title_log_file(const char *path);

/* The console profile name of the user who started the title, its printable
 * ASCII only, into name. Returns 0, or -1 when there is none. */
int ps5_title_user_name(char *name, size_t size);

/* A notification on the console's screen (the shell's pop-up), and the same
 * text to stderr. Returns sceKernelSendNotificationRequest's result. */
int ps5_title_notify(const char *message);

/* One line to stderr (and so klog), flushed. */
void ps5_say(const char *format, ...) __attribute__((format(printf, 1, 2)));

/* Ask the shell to close the title. A title must never call exit(): the
 * console then reports a crash over a run that worked. Never returns. */
__attribute__((noreturn)) void ps5_title_exit(int status);

#ifdef __cplusplus
}
#endif
