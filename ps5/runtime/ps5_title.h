/*
 * C&C Generals PS5 - title lifecycle: logging and the exit through the shell.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#pragma once

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

/* One line to stderr (and so klog), flushed. */
void ps5_say(const char *format, ...) __attribute__((format(printf, 1, 2)));

/* Ask the shell to close the title. A title must never call exit(): the
 * console then reports a crash over a run that worked. Never returns. */
__attribute__((noreturn)) void ps5_title_exit(int status);

#ifdef __cplusplus
}
#endif
