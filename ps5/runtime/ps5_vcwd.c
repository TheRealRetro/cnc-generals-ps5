/*
 * C&C Generals PS5 - a virtual current directory.
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A PS5 title has no current directory worth trusting: getcwd() is not
 * provided and chdir() is refused, while the game (and libc++'s
 * std::filesystem) open everything relative to the game folder. The title is
 * linked with --wrap for the libc path functions (ps5/tools/link-title.sh):
 * each __wrap_ here resolves a relative path against a directory this file
 * keeps, /app0 at start, and calls the real function with the absolute path.
 * chdir() and getcwd() work on that directory. Absolute paths pass through.
 *
 * Only exported names of the console's libc are called (via __real_).
 */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define VCWD_MAX 1024

static char vcwd[VCWD_MAX] = "/app0";
static pthread_mutex_t vcwd_lock = PTHREAD_MUTEX_INITIALIZER;

/* Fold an absolute path's "." and ".." components and repeated slashes into
 * out. Returns out, or NULL (ENAMETOOLONG). */
static const char *fold(const char *absolute, char out[VCWD_MAX])
{
    size_t len = 0;
    const char *p = absolute;
    out[0] = '\0';
    while (*p) {
        while (*p == '/')
            p++;
        const char *start = p;
        while (*p && *p != '/')
            p++;
        const size_t n = (size_t)(p - start);
        if (n == 0 || (n == 1 && start[0] == '.'))
            continue;
        if (n == 2 && start[0] == '.' && start[1] == '.') {
            while (len > 0 && out[len - 1] != '/')
                len--;
            if (len > 0)
                len--; /* the slash */
            out[len] = '\0';
            continue;
        }
        if (len + 1 + n >= VCWD_MAX) {
            errno = ENAMETOOLONG;
            return NULL;
        }
        out[len++] = '/';
        memcpy(out + len, start, n);
        len += n;
        out[len] = '\0';
    }
    if (len == 0) {
        out[0] = '/';
        out[1] = '\0';
    }
    return out;
}

/* Join path onto the virtual directory and fold it. Returns path itself when
 * it is absolute (or NULL or empty), else out (NULL on ENAMETOOLONG). */
static const char *resolve(const char *path, char out[VCWD_MAX])
{
    if (path == NULL || path[0] == '/' || path[0] == '\0')
        return path;

    char joined[VCWD_MAX * 2];
    pthread_mutex_lock(&vcwd_lock);
    snprintf(joined, sizeof(joined), "%s/%s", vcwd, path);
    pthread_mutex_unlock(&vcwd_lock);
    return fold(joined, out);
}

#define RESOLVE(name, path)        \
    char name##_buffer[VCWD_MAX];  \
    const char *name = resolve(path, name##_buffer); \
    if ((path) != NULL && (path)[0] != '\0' && name == NULL) \
        return -1

int __real_open(const char *path, int flags, ...);
int __real_access(const char *path, int mode);
int __real_stat(const char *path, struct stat *st);
int __real_lstat(const char *path, struct stat *st);
int __real_mkdir(const char *path, mode_t mode);
int __real_rmdir(const char *path);
int __real_unlink(const char *path);
int __real_remove(const char *path);
int __real_rename(const char *from, const char *to);
int __real_chmod(const char *path, mode_t mode);
FILE *__real_fopen(const char *path, const char *mode);
FILE *__real_freopen(const char *path, const char *mode, FILE *stream);
DIR *__real_opendir(const char *path);

int __wrap_open(const char *path, int flags, ...)
{
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode = (mode_t)va_arg(args, int);
        va_end(args);
    }
    RESOLVE(full, path);
    return __real_open(full, flags, mode);
}

int __wrap_access(const char *path, int mode)
{
    RESOLVE(full, path);
    return __real_access(full, mode);
}

int __wrap_stat(const char *path, struct stat *st)
{
    RESOLVE(full, path);
    return __real_stat(full, st);
}

int __wrap_lstat(const char *path, struct stat *st)
{
    RESOLVE(full, path);
    return __real_lstat(full, st);
}

int __wrap_mkdir(const char *path, mode_t mode)
{
    RESOLVE(full, path);
    return __real_mkdir(full, mode);
}

int __wrap_rmdir(const char *path)
{
    RESOLVE(full, path);
    return __real_rmdir(full);
}

int __wrap_unlink(const char *path)
{
    RESOLVE(full, path);
    return __real_unlink(full);
}

int __wrap_remove(const char *path)
{
    RESOLVE(full, path);
    return __real_remove(full);
}

int __wrap_rename(const char *from, const char *to)
{
    RESOLVE(full_from, from);
    RESOLVE(full_to, to);
    return __real_rename(full_from, full_to);
}

int __wrap_chmod(const char *path, mode_t mode)
{
    RESOLVE(full, path);
    return __real_chmod(full, mode);
}

FILE *__wrap_fopen(const char *path, const char *mode)
{
    char buffer[VCWD_MAX];
    const char *full = resolve(path, buffer);
    if (path != NULL && path[0] != '\0' && full == NULL)
        return NULL;
    return __real_fopen(full, mode);
}

FILE *__wrap_freopen(const char *path, const char *mode, FILE *stream)
{
    char buffer[VCWD_MAX];
    const char *full = resolve(path, buffer);
    if (path != NULL && path[0] != '\0' && full == NULL)
        return NULL;
    return __real_freopen(full, mode, stream);
}

DIR *__wrap_opendir(const char *path)
{
    char buffer[VCWD_MAX];
    const char *full = resolve(path, buffer);
    if (path != NULL && path[0] != '\0' && full == NULL)
        return NULL;
    return __real_opendir(full);
}

int __wrap_chdir(const char *path)
{
    char buffer[VCWD_MAX];
    const char *full = resolve(path, buffer);
    struct stat st;
    if (full == NULL || full[0] == '\0') {
        errno = full == NULL ? ENAMETOOLONG : ENOENT;
        return -1;
    }
    if (__real_stat(full, &st) != 0)
        return -1;
    if (!S_ISDIR(st.st_mode)) {
        errno = ENOTDIR;
        return -1;
    }
    pthread_mutex_lock(&vcwd_lock);
    snprintf(vcwd, sizeof(vcwd), "%s", full);
    pthread_mutex_unlock(&vcwd_lock);
    return 0;
}

char *__wrap_getcwd(char *buffer, size_t size)
{
    pthread_mutex_lock(&vcwd_lock);
    const size_t len = strlen(vcwd);
    char *result = NULL;
    if (buffer == NULL) {
        result = strdup(vcwd);
    } else if (size > len) {
        memcpy(buffer, vcwd, len + 1);
        result = buffer;
    } else {
        errno = ERANGE;
    }
    pthread_mutex_unlock(&vcwd_lock);
    return result;
}

/* No symbolic links are followed: titles have none of their own. */
char *__wrap_realpath(const char *path, char *resolved)
{
    char buffer[VCWD_MAX];
    struct stat st;
    if (path == NULL) {
        errno = EINVAL;
        return NULL;
    }
    path = path[0] == '/' ? fold(path, buffer) : resolve(path, buffer);
    if (path == NULL)
        return NULL;
    if (__real_stat(path, &st) != 0)
        return NULL;
    if (resolved == NULL)
        return strdup(path);
    snprintf(resolved, PATH_MAX, "%s", path);
    return resolved;
}

/* libc++'s std::filesystem asks pathconf() for limits; no system module a
 * title loads exports it. Bound under libc's name by the link. */
long ps5_title_pathconf(const char *path, int name)
{
    (void)path;
    switch (name) {
    case _PC_LINK_MAX:
        return 32767;
    case _PC_NAME_MAX:
        return 255;
    case _PC_PATH_MAX:
        return VCWD_MAX;
    case _PC_PIPE_BUF:
        return 512;
    default:
        errno = EINVAL;
        return -1;
    }
}
